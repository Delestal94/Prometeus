"""Inspect a GLB without Blender or third-party dependencies.

Usage: python art/gel_character/validate_glb.py path/to/gel_base.glb

Reads only the supplied asset; prints a JSON report and exits nonzero for
invalid indices, skin weights, transforms, geometry or animation samples.
Face meshes and animation clips are optional for the generic base.
"""

import argparse
import json
import math
import struct
import sys
from collections import Counter
from pathlib import Path


COMPONENTS = {
    5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
    5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
          "MAT2": 4, "MAT3": 9, "MAT4": 16}


class Asset:
    def __init__(self, path):
        raw = path.read_bytes()
        if len(raw) < 20:
            raise ValueError("File is shorter than a GLB header")
        magic, version, length = struct.unpack_from("<4sII", raw)
        if magic != b"glTF" or version != 2 or length != len(raw):
            raise ValueError("Invalid GLB magic, version or declared length")
        chunks = {}
        offset = 12
        while offset < len(raw):
            size, kind = struct.unpack_from("<II", raw, offset)
            offset += 8
            if size % 4 or offset + size > len(raw) or kind in chunks:
                raise ValueError("Invalid, duplicated or unaligned GLB chunk")
            chunks[kind] = raw[offset:offset + size]
            offset += size
        self.data = json.loads(chunks[0x4E4F534A])
        self.binary = chunks.get(0x004E4942, b"")
        self.cache = {}
        buffers = self.data.get("buffers", [])
        if len(buffers) != 1 or "uri" in buffers[0]:
            raise ValueError("Expected one embedded GLB buffer")
        if buffers[0]["byteLength"] > len(self.binary):
            raise ValueError("Embedded buffer is truncated")

    def unpack(self, view_id, offset, count, component, kind, packed=False):
        view = self.data["bufferViews"][view_id]
        if view.get("buffer", 0) != 0:
            raise ValueError("Accessor references an external buffer")
        fmt, component_size = COMPONENTS[component]
        width = WIDTHS[kind]
        # Matrix columns with 8/16-bit components are padded to four bytes.
        column = {"MAT2": 2, "MAT3": 3, "MAT4": 4}.get(kind, width)
        column_bytes = component_size * column
        column_stride = (column_bytes + 3) // 4 * 4 if kind.startswith("MAT") else column_bytes
        element_size = column_stride * (width // column)
        stride = element_size if packed else view.get("byteStride", element_size)
        if stride < element_size:
            raise ValueError("Accessor byte stride is smaller than its element")
        if offset < 0 or (count and offset + (count - 1) * stride + element_size > view["byteLength"]):
            raise ValueError("Accessor exceeds its buffer view")
        start = view.get("byteOffset", 0) + offset
        if start + (count - 1) * stride + element_size > len(self.binary):
            raise ValueError("Accessor exceeds embedded buffer")
        return [tuple(struct.unpack_from("<" + fmt, self.binary,
                     start + row * stride + (i // column) * column_stride + (i % column) * component_size)[0]
                     for i in range(width)) for row in range(count)]

    def accessor(self, index):
        if index in self.cache:
            return self.cache[index]
        a = self.data["accessors"][index]
        count, component, kind = a["count"], a["componentType"], a["type"]
        if "bufferView" in a:
            values = self.unpack(a["bufferView"], a.get("byteOffset", 0), count, component, kind)
        else:
            values = [(0,) * WIDTHS[kind] for _ in range(count)]
        if "sparse" in a:
            sparse = a["sparse"]
            indices, replacements = sparse["indices"], sparse["values"]
            slots = self.unpack(indices["bufferView"], indices.get("byteOffset", 0),
                                sparse["count"], indices["componentType"], "SCALAR", True)
            updates = self.unpack(replacements["bufferView"], replacements.get("byteOffset", 0),
                                  sparse["count"], component, kind, True)
            prior = -1
            for slot, replacement in zip(slots, updates):
                if slot[0] <= prior or slot[0] >= count:
                    raise ValueError("Sparse accessor indices are invalid")
                values[slot[0]] = replacement
                prior = slot[0]
        if a.get("normalized", False) and component != 5126:
            maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535, 5125: 4294967295}[component]
            values = [tuple(max(-1., x / maximum) for x in row) for row in values]
        self.cache[index] = values
        return values


def validate(path, max_triangles=None):
    asset = Asset(path)
    doc = asset.data
    errors, warnings = [], []

    def require(ok, message):
        if not ok:
            errors.append(message)

    nodes = doc.get("nodes", [])
    skins = doc.get("skins", [])
    meshes = doc.get("meshes", [])
    require(bool(skins), "Asset has no skin")
    require(bool(meshes), "Asset has no geometry")
    for i in range(len(doc.get("accessors", []))):
        require(all(math.isfinite(x) for row in asset.accessor(i) for x in row),
                f"Accessor {i} contains a non-finite value")
    for i, node in enumerate(nodes):
        for key in ("matrix", "translation", "rotation", "scale"):
            require(all(math.isfinite(v) for v in node.get(key, [])), f"Node {i} has a non-finite {key}")
        for child in node.get("children", []):
            require(0 <= child < len(nodes), f"Node {i} has invalid child {child}")
    skin_report = []
    for i, skin in enumerate(skins):
        joints = skin["joints"]
        require(len(joints) == len(set(joints)), f"Skin {i} has duplicate joints")
        require(all(0 <= j < len(nodes) for j in joints), f"Skin {i} references invalid joints")
        if "inverseBindMatrices" in skin:
            a = doc["accessors"][skin["inverseBindMatrices"]]
            require(a["type"] == "MAT4" and a["count"] == len(joints),
                    f"Skin {i} has an invalid inverse bind matrix accessor")
        skin_report.append({"joints": len(joints), "names": [nodes[j].get("name", str(j)) for j in joints]})

    mesh_report, triangles = [], 0
    max_weight_error, max_influences, unweighted = 0., 0, 0
    for node_id, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = meshes[node["mesh"]]
        name = node.get("name", mesh.get("name", str(node_id)))
        skin = skins[node["skin"]] if "skin" in node else None
        entry = {"name": name, "skinned": skin is not None, "vertices": 0, "triangles": 0}
        for primitive in mesh["primitives"]:
            attrs = primitive["attributes"]
            positions = asset.accessor(attrs["POSITION"])
            count = len(positions)
            entry["vertices"] += count
            require(count > 0, f"Mesh {name} contains empty geometry")
            for semantic, accessor_id in attrs.items():
                require(len(asset.accessor(accessor_id)) == count, f"Mesh {name} {semantic} has wrong vertex count")
            indices = asset.accessor(primitive["indices"]) if "indices" in primitive else [(i,) for i in range(count)]
            require(all(0 <= x[0] < count for x in indices), f"Mesh {name} has out-of-range triangle indices")
            if primitive.get("mode", 4) == 4:
                require(len(indices) % 3 == 0, f"Mesh {name} has an incomplete triangle")
                entry["triangles"] += len(indices) // 3
            else:
                warnings.append(f"Mesh {name} uses primitive mode {primitive['mode']}; triangle count omits it")
            if skin is None:
                continue
            sets = sorted(key for key in attrs if key.startswith("WEIGHTS_"))
            require(bool(sets), f"Skinned mesh {name} has no vertex weights")
            weights, joints = [], []
            for key in sets:
                joint_key = key.replace("WEIGHTS_", "JOINTS_")
                require(joint_key in attrs, f"Mesh {name} is missing {joint_key}")
                weights.append(asset.accessor(attrs[key]))
                joints.append(asset.accessor(attrs[joint_key]))
            for vertex in range(count):
                influences = [(j, w) for jj, ww in zip(joints, weights)
                              for j, w in zip(jj[vertex], ww[vertex])]
                total = sum(w for _, w in influences)
                max_weight_error = max(max_weight_error, abs(total - 1.))
                max_influences = max(max_influences, sum(w > 1e-6 for _, w in influences))
                unweighted += int(total <= 0)
                if any(w < 0 or j < 0 or j >= len(skin["joints"]) for j, w in influences):
                    errors.append(f"Mesh {name} has invalid weight/joint at vertex {vertex}")
                    break
        triangles += entry["triangles"]
        mesh_report.append(entry)
    require(max_weight_error < 1e-4, f"Skin weights are not normalized (max error {max_weight_error:.6g})")
    require(unweighted == 0, f"Found {unweighted} unweighted skinned vertices")
    require(max_influences <= 4, f"Skin uses {max_influences} influences per vertex; expected at most four")
    if max_triangles is not None:
        require(triangles <= max_triangles, f"Triangle budget exceeded: {triangles} > {max_triangles}")

    animation_report = []
    names = Counter(a.get("name", "") for a in doc.get("animations", []))
    require(all(n == 1 for n in names.values()), "Duplicate animation names")
    for animation in doc.get("animations", []):
        name = animation.get("name", "<unnamed>")
        duration, channels = 0., set()
        for channel in animation["channels"]:
            target = channel["target"]
            require(0 <= target["node"] < len(nodes), f"Animation {name} targets an invalid node")
            identifier = (target["node"], target["path"])
            require(identifier not in channels, f"Animation {name} repeats target {identifier}")
            channels.add(identifier)
            sampler = animation["samplers"][channel["sampler"]]
            times = [x[0] for x in asset.accessor(sampler["input"])]
            values = asset.accessor(sampler["output"])
            require(bool(times) and times[0] >= 0 and all(b > a for a, b in zip(times, times[1:])),
                    f"Animation {name} has invalid sample times")
            if times:
                duration = max(duration, times[-1])
            cubic = sampler.get("interpolation", "LINEAR") == "CUBICSPLINE"
            samples = values[1::3] if cubic else values
            if target["path"] != "weights":
                require(len(values) == len(times) * (3 if cubic else 1), f"Animation {name} has wrong sample count")
            if target["path"] == "rotation":
                require(all(abs(sum(x * x for x in row) - 1) < .01 for row in samples),
                        f"Animation {name} contains a non-unit quaternion")
        animation_report.append({"name": name, "duration_seconds": round(duration, 6), "channels": len(channels)})
    return {"file": str(path.resolve()), "valid": not errors, "errors": errors,
            "warnings": warnings, "triangles": triangles, "meshes": mesh_report,
            "skins": skin_report, "animations": animation_report,
            "optional_face_meshes": [m["name"] for m in mesh_report
                                     if any(term in m["name"].lower() for term in ("eye", "mouth", "face"))],
            "weights": {"max_sum_error": max_weight_error, "max_influences": max_influences,
                        "unweighted_vertices": unweighted}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", type=Path)
    parser.add_argument("--max-triangles", type=int, help="Optional geometry budget")
    args = parser.parse_args()
    try:
        report = validate(args.glb, args.max_triangles)
    except (OSError, ValueError, KeyError, IndexError, struct.error) as error:
        report = {"file": str(args.glb), "valid": False, "errors": [str(error)]}
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
