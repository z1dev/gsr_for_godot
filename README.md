# Grab-Scale-Rotate for Godot
Enables manipulating objects in Godot's 3D editor with shortcut keys like how it's done in Blender, and other usability features.

### Features
* G-S-R shortcut keys for grab, scale and rotate, with axis limit or exlusion, snapping and numeric entry.
* Place objects in a grid pattern on any axis. Similar to GridMap, but creates real separate scenes.
* Selection of meshes behind other meshes by clicking at the same screen position. (Currently only detects meshes, not collision shapes or other objects. This functionality is planned.)

### Installation
Place the addons folder with its contents into the project root, like any other Godot plugin, and enable plugin in the project settings.

#### IMPORTANT:
Godot uses some shortcut keys this plugin also uses. Remove or change them in your "Editor Settings" (**not** Project Settings.)  See list below.
Only shortcuts that are general or specific to the 3d (Spatial) view need to be changed.

## How to use
First install then activate the plugin in the project settings. The plugin uses shortcut keys for every action. These are listed below.
Some keys, like the r and y clash with Godot's defaults. Currently it's not possible to change these without changing the plugin's code.
Please disable or change them in Godot's "Editor Settings".

#### Options menu:
![gsr_menu](https://user-images.githubusercontent.com/30132426/135284581-9a72d9b9-5d80-4abc-a4cd-e1bf71380c94.png)
* Z for up - Swaps the z and y shortcut keys for people who want the same shortcuts Blender uses.
* Snap options - adds a bar below the 3d view to change snap options any time.
* Smart select - This is an experimental feature. Allows selecting objects behind other objects by clicking in the same screen position multiple times. Currently only works for scene tree nodes that are MeshInstance objects or have MeshInstance children in their scene.
* Unpack scene... - Helper to save all scenes of the current open scene in their own files. Useful when creating tiles in Blender and exporting them in a single file. It's advised to open every created scene file, move them to the origin point and save. Saving a file will also create a thumbnail for the file system panel.

#### Grab, scale and rotate:
Grab (move), scale or rotate selected object or objects like in Blender. Press and release the shortcut key to start the action. Right click/escape cancels it. Left clicking or pressing enter finalizes the change.
Key|Action|Conflicts with default
---|------|----------------------
g|Grab (move) nodes in the 3d view|No
s|Scale nodes based on mouse distance|No
r|Rotate nodes around their pivot|**Yes**

Shortcuts that work during the actions:
Key|Action|Conflict with defaults
---|------|----------------------
x, y, z|Limit action to the specific axis|**y only**
xx, yy, zz|Limit action to local/global axis|**y only**
shift+x/+y/+z|Exclude local/global axis and limit movement to the others|**y only**
hold shift|Make smaller adjustment|No
hold ctrl|Enable/disable snapping|No
numbers|Enter exact delta value while limited to axis|No

#### Snap to grid:
Add a scene at a grid positions or move selected scene on the grid. The grid can be vertical or horizontal relative to the parent. Only one scene is affected at a time.
For the "add" action, the scene file to be added must be selected in the filesystem panel. It'll be added as a child of the currently selected node. To make this easier, toggle "split mode" of the filesystem panel, and show files as thumbnails.

![split_mode](https://user-images.githubusercontent.com/30132426/135285467-a77c616f-7833-4dae-b449-9113d1a72b2e.png)

Key|Action|Conflicts with default
---|------|----------------------
a|Add new instance of selected scene file|No
m|Move the selected spatial node on the grid|No
d|Duplicate selected node and move copy on the grid|No

Shortcuts that work during the actions:
Key|Action|Conflict with defaults
---|------|----------------------
x, y, z|Modify grid axis or limit movement, see explanation|**y only**
hold shift|Move on subdivided grid|No
s|Scale node. Shortcuts for scale apply|No
r|Rotate node. Shortcuts for rotate apply|**Yes**

The result of pressing an axis key will depend on the grid's current orientation. If the grid is not oriented towards the axis, it'll change to the corresponding orientation. If it does, you can move the grid along the axis. For example pressing x will make the grid look towards the x axis. Pressing x again you can move it "left" and "right" on that axis. Pressing x a third time, or clicking with the mouse will save the grid position, and allow moving the scene on the grid.
