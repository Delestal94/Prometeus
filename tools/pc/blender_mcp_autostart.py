# Makes sure the "MCP for Blender" socket server (port 9876) is up once Blender's UI loads,
# so the unattended PC routines (tools/pc/rutina-pc.ps1) can drive Blender without anyone
# pressing "Connect to Claude". The addon usually starts it on register already; this
# enables the addon if it is off and is a no-op when the server is running.
# Run as: blender.exe --python blender_mcp_autostart.py
import addon_utils
import bpy

ADDON_MODULE = "addon"  # the addon lives in scripts/addons/addon.py


def _start_server():
    if not hasattr(bpy.ops, "blendermcp"):
        addon_utils.enable(ADDON_MODULE, default_set=True, persistent=True)
    try:
        bpy.ops.blendermcp.start_server()
    except Exception as exc:  # retry: the operator can fail while the UI is still loading
        print(f"[mcp-autostart] start_server failed, retrying: {exc}")
        return 2.0
    print("[mcp-autostart] MCP for Blender server started")
    return None


bpy.app.timers.register(_start_server, first_interval=2.0)
