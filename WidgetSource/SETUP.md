# Adding the desktop widget

Five steps in Xcode. Nothing here touches the database — the widget reads a small JSON
file the app writes, so your accounts and loans stay exactly where they are.

## 1. Create the target

**File → New → Target… → macOS → Widget Extension**

- Product Name: **TranquilWidget**
- Uncheck **Include Live Activity** and **Include Configuration App Intent**
- Finish → **Activate** when prompted

Xcode creates a `TranquilWidget/` folder with template files.

## 2. Replace the template

Delete the files Xcode generated inside `TranquilWidget/` (`TranquilWidget.swift`,
`TranquilWidgetBundle.swift`, `AppIntent.swift` if present — keep `Assets.xcassets` and
`Info.plist`).

Then copy in, from `WidgetSource/`:

- `TranquilWidget.swift`   → into `TranquilWidget/`
- `WidgetSnapshot.swift`   → into `TranquilWidget/`

## 3. Share the snapshot type with the app

Select **`WidgetSnapshot.swift`** in the navigator. In the File Inspector on the right,
under **Target Membership**, tick **both**:

- ☑ MyFinances
- ☑ TranquilWidget

That one file is the contract between the two processes. Everything else stays separate.

Then delete `MyFinances/Services/WidgetSnapshot.swift` — it was a placeholder so the app
would build before the widget existed, and two copies would collide.

## 4. Turn on the App Group — on both targets

For **MyFinances**, then again for **TranquilWidget**:

**Signing & Capabilities → + Capability → App Groups → +**

Add exactly: `group.com.MyFinances`

Both targets must show it ticked. This is the shared folder the snapshot file lives in;
without it the widget has no way to see the app's data.

## 5. Build and add it

Build and run the app once — that writes the first snapshot.

Then right-click the desktop → **Edit Widgets**, find **Tranquil**, and drag the size you
want. Small, medium and large are all supported.

---

## If the widget shows sample numbers

It is showing the placeholder, which means it could not read the snapshot. In order of
likelihood:

1. The App Group is missing or differently spelled on one of the two targets.
2. The app has not been run since the group was added — run it once.
3. `WidgetSnapshot.swift` is not a member of both targets.

## What it shows

- **Free to spend this week**, or available to spend before you have any commitments
- Spent today and this week
- Runway, stability score, current streak
- The one next action from the Ladder
- The next scheduled outgoing
- One warning, if anything needs attention

It refreshes whenever you log something, and at least every two hours otherwise.

## Why there are no buttons

Widgets cannot take typed input. A button could log a fixed amount, but ⌥⌘E opens quick
capture from any app and lets you type the real number, which is both faster and honest.
