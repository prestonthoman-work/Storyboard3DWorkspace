# Storyboard 3D

A visionOS app for planning a film shot by shot. You set up a small 3D set on a real table, arrange objects, save keyframes, and photograph each shot from where you're standing. The result is a storyboard you can play full screen or export as a video or a printable sheet.

## How it works

1. **Set the stage.** The round base finds a table in your room and sits on it. If no table is found, it floats in front of you. Choose a surface, resize the base or spin it by its edge, and pick a backdrop (a built-in sky or your own image).
2. **Build the set.** Place objects from the library, or type a prompt. Pinch and drag to arrange them; they fall under gravity and stack on each other.
   **Characters.** Three built-in poseable figures (Mannequin, Child, Stocky Figure) share one 17-joint rig: hips, waist, chest, neck and head, plus a shoulder, elbow and hand on each arm and a hip, knee and foot on each leg. Select one and switch between **Move Character** (place, turn, resize) and **Pose Character**. In Pose mode you pick a body part by tapping it or from the list, and turn it with labeled sliders or 5° steps. Every joint has limits, and each joint or the whole pose can be reset. For a hand or foot, **Place Hand/Foot** uses inverse kinematics: drag the blue target in the scene, or set Forward/Up/Out, and the arm or leg bends to reach, with an elbow or knee direction control. Ten presets are included (sitting says it needs a prop to sit on), and you can save your own poses for any project. For hands-on posing, **Open Pose Studio** shows the selected character about 55 cm tall in its own volume: pinch any body part and drag to swing it, drag the blue target to place a hand or foot, and drag the floor (or use the front/side/back buttons) to look from any side. Edits go straight to the character in the scene, with undo. Joint markers and the reach target only appear while posing and never show up in photos or exports.
3. **Animate.** A keyframe saves where everything is, including each character's pose. Move things and add another keyframe, and playback glides between them. Choose **Hold, then Cut** on a keyframe to keep its poses until the next one, for storyboards of distinct poses. Each keyframe can hold a shot type (wide, close-up, and so on) and notes, which you can type or dictate.
4. **Shoot.** Look at the scene through the viewfinder and take a photo for each keyframe. Lens, lighting and film look are adjustable, and photos re-render automatically when their keyframe changes.
5. **Share.** Play the storyboard full screen, or export:
   - an **animatic** (MP4): objects move while the camera glides between your photo angles
   - a **slideshow** (MP4) of each keyframe's photo, with optional captions
   - a **storyboard sheet** (PDF), with 2, 6 or 12 shots per page

Projects save automatically. If a save fails, the workspace shows a banner with a Try Again button, and the app won't switch projects until the changes are saved.

> **Characters and imported models.** Only the built-in characters are poseable. The app has no 3D model import, and generated or sample objects can only be moved as a whole; nothing is rigged automatically.

> **Prompts are sample-only.** No AI model generation is connected yet. Prompts are matched against the built-in object catalog, and anything unknown becomes a placeholder. To connect a real service, see `ModelGenerationServiceProvider` in `Services/ModelGenerationService.swift`.

## Requirements

- Xcode with the visionOS 27.2 SDK
- Apple Vision Pro, or the visionOS Simulator. The Simulator has no table detection, so the base floats in front of you there.

The app asks for these permissions:

| Permission | Used for |
| --- | --- |
| World sensing | Finding tables to put the base on |
| Microphone and speech recognition | Dictating shot notes |
| Add to Photos | Saving a captured shot to Photos |

## Build and run

Open `Storyboard3DWorkspace.xcodeproj` in Xcode, select the **Storyboard3DWorkspace** scheme and a Vision Pro destination, then press Run.

From the command line:

```sh
xcodebuild build -scheme Storyboard3DWorkspace \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

## Tests

The tests use Swift Testing and run on the Simulator:

```sh
xcodebuild test -scheme Storyboard3DWorkspace \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

Tests that save projects point `ProjectStore.storageOverride` at a temporary folder, so your real projects are never read or changed.

## Code layout

| Folder | What's in it |
| --- | --- |
| `AppModel.swift` | App-wide state: the open project, objects, keyframes, capture, undo, and saving. Views read and change the app through it. |
| `Models/` | Value types and small controllers: keyframe timeline and animator, photo library, camera paths, capture settings, export (`ExportController`). |
| `Scene/` | RealityKit content: the workspace scene, base templates, sample objects, gravity, selection handles, table anchoring (`TableAnchoring`). |
| `Services/` | Rendering, export writers, project storage (`ProjectStore`), spatial tracking, dictation, and model generation. |
| `Views/` | SwiftUI panels and windows: the workspace tabs, timeline window, storyboard viewer, projects list. |

Projects are stored in Application Support under `Projects/<id>/`. The comment at the top of `Services/ProjectStore.swift` describes the files in each project folder.
