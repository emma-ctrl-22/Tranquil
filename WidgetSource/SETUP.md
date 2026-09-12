# Adding the desktop widget

> **This has already been done on Emmanuel's Mac.** These notes are the record of how,
> so it can be repeated on another machine or after a fresh clone. The widget source
> itself lives in `TranquilWidget/`.


Five steps in Xcode. Nothing here touches the database — the widget reads a small JSON
file the app writes, so your accounts and loans stay exactly where they are.

## 1. Create the target

**File → New → Target… → macOS → Widget Extension**

- Product Name: **TranquilWidget** — Xcode will call the target `TranquilWidgetExtension`
- Uncheck **Include Live Activity** and **Include Configuration App Intent**
- Finish → **Activate** when prompted

Xcode creates a `TranquilWidget/` folder with template files.

## 2. Replace the template

Delete the files Xcode generated inside `TranquilWidget/` (`TranquilWidget.swift`,
`TranquilWidgetBundle.swift`, `TranquilWidgetControl.swift`, `AppIntent.swift` if
present — keep `Assets.xcassets` and `Info.plist`).

The real widget source now lives in **`TranquilWidget/`** in this repository —
`TranquilWidget.swift` and `WidgetSnapshot.swift`. There is deliberately no second copy
kept here: two copies of the same file drift, and the drift is silent.

## 3. Share the snapshot type with the app

> Xcode names the target **TranquilWidgetExtension**, not TranquilWidget. And because
> both folders are synchronized groups, a file does **not** get tick-boxes for other
> targets — you add membership with the **+** button instead.

Select **`TranquilWidget/WidgetSnapshot.swift`** in the navigator. In the File Inspector
on the right (the ⌥⌘1 pane), find **Target Membership**. It will list only
`TranquilWidgetExtension`.

Click the **+** button at the bottom of that list and choose **MyFinances**.

Both should now be listed. That one file is the contract between the two processes;
everything else stays separate.

*(The old `MyFinances/Services/WidgetSnapshot.swift` has already been deleted — two
copies would be a duplicate-symbol error.)*

## 4. Turn on the App Group — on both targets

> You do **not** need a paid Apple Developer account. The free personal team created
> from your Apple ID is enough to run this on your own Mac.


For **MyFinances**, then again for **TranquilWidgetExtension**:

**Signing & Capabilities → + Capability → App Groups → +**

Add exactly:

```
VZ4AFL6ZHN.group.com.MyFinances
```

**The Team ID prefix is required on macOS.** On iOS a plain `group.something` works; on
macOS the container will not resolve without it. Xcode may offer `$(TeamIdentifierPrefix)`
— typing the ID out in full is equivalent and easier to check.

Both targets must show it ticked. This is the shared folder the snapshot file lives in;
without it the widget has no way to see the app's data.

## 5. Build and add it

Build and run the app once — that writes the first snapshot.

Then right-click the desktop → **Edit Widgets**, find **Tranquil**, and drag the size you
want. Small, medium and large are all supported.

---

## If the widget cannot read your data

It will **say so** rather than show sample numbers. The message tells you which fault it
is:

| It says | What to do |
|---|---|
| Can't reach shared data | The App Group is missing, or missing the `VZ4AFL6ZHN.` prefix, on one of the two targets |
| Open Tranquil once | The container is fine; launch the app and it fills in |
| Update Tranquil | App and widget are different builds — rebuild both |
| Data unreadable | The snapshot file will not decode; delete it and relaunch the app |

Sample figures appear in exactly one place: the widget gallery preview, before you have
placed it.

## After changing widget code

Build **clean** before installing. An incremental build can leave the app with a new
snapshot format and an old writer, which produces a file with empty fields — and looks
exactly like the widget being broken.

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
