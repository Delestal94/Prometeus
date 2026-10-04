"""Deterministic endpoint simplification checked against finite morph/pose samples.

Returned source indices preserve positions, morph deltas and skin weights exactly.
This is sampled evidence, not certification of the continuous deformation space.
"""
import heapq
from collections import Counter
import numpy as np


def simplify_morph_safe(points, triangles, morph_samples, *, target_triangles=794,
                        protected_vertices=(), pose_samples=None,
                        pose_normal_matrices=None):
    """Return source indices, remapped triangles and actual collapse statistics.

    Morph samples include the baseline first. Optional pose matrices are each
    source vertex's inverse-transpose blended skin matrix, in the same order as
    pose samples. Local contact tests use the exported-geometry validator's
    authoritative predicate. The caller must supply a closed source that has
    already passed its finite contact sweep; unchanged faces are not retested.
    """
    from gel_body_validation import EPS, triangle_intersection
    points = np.asarray(points, dtype=np.float64)
    samples = np.asarray(morph_samples, dtype=np.float64)
    if points.ndim!=2 or points.shape[1]!=3 or len(points)<4:
        raise ValueError('Source points must be at least four XYZ vertices')
    if samples.ndim != 3 or samples.shape[1:] != points.shape or not len(samples):
        raise ValueError('Morph samples must be sample × source vertex × XYZ')
    if not np.array_equal(samples[0], points):
        raise ValueError('The first morph sample must be the exact source baseline')
    if not np.isfinite(samples).all():
        raise ValueError('Non-finite source deformation')
    morph_count = len(samples)
    pose_count = 0
    if pose_samples is not None:
        pose_samples = np.asarray(pose_samples, dtype=np.float64)
        pose_normal_matrices = np.asarray(pose_normal_matrices, dtype=np.float64)
        if pose_samples.ndim!=3 or pose_samples.shape[1:] != points.shape or not len(pose_samples):
            raise ValueError('Pose sample vertex order differs from the source')
        if pose_normal_matrices.shape != (len(pose_samples),len(points),3,3):
            raise ValueError('Pose normal matrices must match every source vertex')
        if not np.isfinite(pose_samples).all() or not np.isfinite(pose_normal_matrices).all():
            raise ValueError('Non-finite pose deformation')
        pose_count = len(pose_samples)
        samples = np.concatenate((samples,pose_samples))
    faces = np.asarray(triangles)
    if (faces.ndim!=2 or faces.shape[1]!=3 or len(faces)<4
            or faces.dtype.kind not in 'iu' or np.any(faces<0) or np.any(faces>=len(points))):
        raise ValueError('Source faces must be triangles with valid integer vertex indices')
    faces = faces.astype(np.int64,copy=True)
    keys = [tuple(sorted(face)) for face in faces]
    if len(set(keys))!=len(keys) or any(len(set(face))!=3 for face in faces):
        raise ValueError('Source faces must not be duplicated or repeat a vertex')
    edge_counts = Counter(tuple(sorted((int(face[i]),int(face[(i+1)%3])))) for face in faces for i in range(3))
    if any(count!=2 for count in edge_counts.values()):
        raise ValueError('Source must be a closed manifold triangle surface')
    active = np.ones(len(faces),dtype=bool)
    alive = np.ones(len(points),dtype=bool)
    versions = np.zeros(len(points),dtype=np.int64)
    protected = set(protected_vertices)
    if any(not isinstance(i,(int,np.integer)) or i<0 or i>=len(points) for i in protected):
        raise ValueError('Protected vertices must be valid source vertex indices')
    vertex_faces = [set() for _ in points]
    for fi,face in enumerate(faces):
        for i in face:
            vertex_faces[i].add(fi)
    def face_normals(indices):
        coordinates = samples[:,indices,:]
        return np.cross(coordinates[:,:,1]-coordinates[:,:,0],
                        coordinates[:,:,2]-coordinates[:,:,0])
    normals = face_normals(faces)
    lengths = np.linalg.norm(normals,axis=2)
    if np.any(lengths<=EPS):
        raise ValueError('The supplied source has a degenerate sampled face')
    planes = np.concatenate((normals/lengths[:,:,None],
        -np.sum(normals/lengths[:,:,None]*samples[:,faces[:,0],:],axis=2)[:,:,None]),axis=2)
    quadrics = np.zeros((len(points),len(samples),4,4),dtype=np.float64)
    for fi,face in enumerate(faces):
        q = np.einsum('si,sj->sij',planes[:,fi],planes[:,fi])*lengths[:,fi,None,None]
        for i in face:
            quadrics[i] += q
    homogeneous = np.concatenate((samples,np.ones((*samples.shape[:2],1))),axis=2)
    minima = samples[:,faces,:].min(axis=2)
    maxima = samples[:,faces,:].max(axis=2)
    heap = []
    stats = dict(collapses=0,rejected_topology=0,rejected_orientation=0,
                 rejected_contacts=0,morph_sample_count=morph_count,pose_sample_count=pose_count)
    def neighbors(i):
        return {int(v) for fi in vertex_faces[i] for v in faces[fi] if v!=i}
    def push(a,b):
        if a>b:a,b=b,a
        if a==b or not alive[a] or not alive[b]:return
        q = quadrics[a]+quadrics[b]
        for keep,remove in ((a,b),(b,a)):
            if remove in protected:continue
            h = homogeneous[:,keep]
            cost = float(np.max(np.einsum('si,sij,sj->s',h,q,h)))
            cost += float(np.max(np.sum((samples[:,a]-samples[:,b])**2,axis=1)))*1e-7
            heapq.heappush(heap,(max(0.,cost),keep,remove,int(versions[keep]),int(versions[remove])))
    edges = {tuple(sorted((int(face[i]),int(face[(i+1)%3])))) for face in faces for i in range(3)}
    for a,b in sorted(edges):push(a,b)
    count = len(faces)
    while heap and count>target_triangles:
        _,keep,remove,kv,rv = heapq.heappop(heap)
        if not alive[keep] or not alive[remove] or versions[keep]!=kv or versions[remove]!=rv:
            continue
        common = vertex_faces[keep]&vertex_faces[remove]
        opposite = {int(v) for fi in common for v in faces[fi] if v not in (keep,remove)}
        if len(common)!=2 or len(opposite)!=2 or neighbors(keep)&neighbors(remove)!=opposite:
            stats['rejected_topology']+=1
            continue
        affected = sorted(vertex_faces[remove]-common)
        proposed = faces[affected].copy()
        proposed[proposed==remove] = keep
        excluded = common|set(affected)
        # A tetrahedral edge passes the vertex-neighbor link test but its two
        # remaining faces become duplicates with opposite winding and zero volume.
        # Also reject a proposed face matching an unchanged face at the kept vertex.
        keys = [tuple(sorted(face)) for face in proposed]
        duplicates = len(set(keys))!=len(keys)
        for a,b,c in proposed:
            if (vertex_faces[a]&vertex_faces[b]&vertex_faces[c])-excluded:
                duplicates = True
                break
        if duplicates:
            stats['rejected_topology']+=1
            continue
        new_normals = face_normals(proposed)
        base_normals = new_normals[0]
        if (np.any(np.sum(new_normals*new_normals,axis=2)<=EPS*EPS)
                or np.any(np.sum(new_normals[:morph_count]*base_normals[None,:,:],axis=2)<=0)
                or np.any(np.sum(new_normals[0]*normals[0,affected],axis=1)<=0)):
            stats['rejected_orientation']+=1
            continue
        if pose_count:
            expected = np.einsum('pfvij,fj->pfi',
                pose_normal_matrices[:,proposed,:,:],base_normals)
            if np.any(np.sum(new_normals[morph_count:]*expected,axis=2)<=0):
                stats['rejected_orientation']+=1
                continue
        # Only these new faces can introduce an intersection. Unchanged faces
        # already passed the same finite source sweep. Preserve the validator's
        # exact adjacency/contact definition, including triangles sharing a point.
        candidate_coordinates = samples[:,proposed,:]
        lo = candidate_coordinates.min(axis=2)
        hi = candidate_coordinates.max(axis=2)
        contacts = False
        # Topology does not vary between deformation samples. Compute precisely
        # the former excluded/shared-edge filter once, retaining point contacts.
        eligible = np.broadcast_to(active,(len(proposed),len(faces))).copy()
        eligible[:,list(excluded)] = False
        shared = np.zeros(eligible.shape,dtype=np.int8)
        for vertex in range(3):
            shared += np.any(faces[None,:,:]==proposed[:,vertex,None,None],axis=2)
        eligible &= shared<2
        previous_faces = [[previous for previous in range(index)
                           if len(set(face)&set(proposed[previous]))<2]
                          for index,face in enumerate(proposed)]
        # Eight-sample chunks bound temporary memory. Component-wise boolean
        # comparisons avoid repeated XYZ reduction allocations; inequalities,
        # EPS, predicate calls and sample/face/other ordering remain unchanged.
        for first in range(0,len(samples),8):
            last = min(first+8,len(samples))
            possible = np.broadcast_to(eligible,(last-first,*eligible.shape)).copy()
            for axis in range(3):
                possible &= minima[first:last,None,:,axis]<=hi[first:last,:,None,axis]+EPS
                possible &= maxima[first:last,None,:,axis]>=lo[first:last,:,None,axis]-EPS
            for sample in range(first,last):
                for index,face in enumerate(proposed):
                    for other in np.flatnonzero(possible[sample-first,index]):
                        if triangle_intersection(candidate_coordinates[sample,index].tolist(),
                                                 samples[sample,faces[other]].tolist()):
                            contacts = True
                            break
                    if contacts:break
                    for previous in previous_faces[index]:
                        if triangle_intersection(candidate_coordinates[sample,index].tolist(),
                                                 candidate_coordinates[sample,previous].tolist()):
                            contacts = True
                            break
                    if contacts:break
                if contacts:break
            if contacts:break
        if contacts:
            stats['rejected_contacts']+=1
            continue
        touched = neighbors(keep)|neighbors(remove)|{keep,remove}
        for fi in sorted(common|set(affected)):
            for i in faces[fi]:vertex_faces[i].remove(fi)
        for fi in common:active[fi]=False
        for fi,face in zip(affected,proposed):
            faces[fi]=face
            for i in face:vertex_faces[i].add(fi)
        normals[:,affected] = new_normals
        minima[:,affected] = lo
        maxima[:,affected] = hi
        quadrics[keep] += quadrics[remove]
        alive[remove] = False
        versions[list(touched)] += 1
        count -= len(common)
        stats['collapses']+=1
        updated_edges = {tuple(sorted((a,b))) for a in touched-{remove} for b in neighbors(a)}
        for a,b in sorted(updated_edges):push(a,b)
        if stats['collapses']%100==0:
            print('Morph-safe LOD triangles:',count,flush=True)
    kept = np.flatnonzero(alive)
    mapping = np.full(len(points),-1,dtype=np.int64)
    mapping[kept] = np.arange(len(kept))
    stats['triangle_count'] = count
    stats['source_vertex_count'] = len(points)
    stats['vertex_count'] = len(kept)
    stats['target_reached'] = count<=target_triangles
    return kept.tolist(),mapping[faces[active]].tolist(),stats
