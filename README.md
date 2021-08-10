# Grab-Scale-Rotate for Godot
Enables manipulating objects in Godot's 3D editor with shortcut keys like how it's done in Blender.

### Installation
Place the addons folder with its contents into the project root, like any other Godot plugin, and enable plugin in the project settings.

#### IMPORTANT:
Godot uses some shortcut keys this plugin also uses. Remove or change them in your "Editor Settings" (**not** Project Settings.)  See list below.

## How to use
With this plugin the familiar **g**, **s** and **r** shortcut keys will be available in Godot's 3d (spatial) editor.
You will be able to grab, scale and rotate like in Blender, limit the action to an axis, or use number keys to enter exact amount of change.

The following shortcut keys are used by this plugin:

Key|Action
---|------
g|Grab (move) nodes in the 3d view
s|Scale nodes based on distance moved
r|Rotate nodes around their pivot
x, y, z|Limit action to the specific axis
xx, yy, zz|Limit action to local/global axis
hold shift|Make smaller adjustment
hold ctrl|Enable/disable snapping

Some keys, like the r and y clash with Godot's defaults. Currently it's not possible to change these without changing the plugin's code.
Please disable them in Godot's "Editor Settings".
