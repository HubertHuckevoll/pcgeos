Imagine a folder called DISTAPPS under SYSAPPL. It contains all the GEOS applications of an Ensemble build. Then there is a preferences module that reads that folder and displays a list of all these applications. The clou: the preferences module checks for links to these applications in WORLD and/or DESKTOP. If an app has a link, it checks a select box or toggle on the app item in the pref module. If not - not. If an app is not selected and you do select it, a Link is created in WORLD/DESKTOP that can then be managed using GeoManager ot the Desktop. This way, all the apps stay in a folder and can be updated anytime that is needed with a distro update. Does that make sense?

Yes, that model maps cleanly onto how GEOS is already structured and can be implemented with existing file/link mechanisms.

Why it fits GEOS conventions

    System apps live under SP_SYS_APPLICATION (commonly SYSTEM\SYSAPPL) and user‑launchable apps under SP_APPLICATION (commonly WORLD) per the standard path definitions in TechDocs/Markdown/Concepts/cfile.md. Keeping the real apps in a SYSAPPL\DISTAPPS subtree is consistent with “system app” semantics.

    Desktop/GeoManager link state is represented via file links plus desktop metadata (see Include/file.def for FileCreateLink/FileReadLink and Include/newdesk.def for DesktopInfo/FEA_DESKTOP_INFO usage). That matches your “selected = link exists” toggle model.

    Be aware that some products store desktop links in the INI (see GPC_DESKTOP_LINKS_IN_INI in Include/product.def), so the preference module may need to respect that setting when determining whether a “link exists.”

Practical mapping to your idea

    Enumerate SYSTEM\SYSAPPL\DISTAPPS (or a standard path that resolves there).

    For each app, check for an existing link in WORLD and/or the Desktop’s folder (often SP_TOP\DESKTOP in practice) by:

        locating a link file whose target points back to the app (via FileReadLink), and/or

        inspecting FEA_DESKTOP_INFO as needed for Desktop object type.

    On toggle “on,” create a link in WORLD/DESKTOP with FileCreateLink and set desktop info if required.

    On toggle “off,” delete the link.

This preserves clean app storage in SYSAPPL\DISTAPPS while still letting users manage visible entries through the Desktop/GeoManager.


Create a new Preferences module under Appl/Preferences (or the product’s preferred preferences location). Define a UI list (GenItemGroup/GenBooleanGroup or similar) bound to an internal model of discovered apps in SYSTEM\SYSAPPL\DISTAPPS. Ensure the list can show each app’s display name and a toggle state. Use GOC conventions and C89 variable declaration rules.


Implement a scan routine that resolves SP\_SYS\_APPLICATION (from file.def/standard paths) and appends the DISTAPPS subdir. Use FileEnum or equivalent kernel routines to enumerate geodes. Extract a display name (from token/moniker or filename) and store it in the model. Avoid large local buffers; use MemAlloc with HAF\_ZERO\_INIT and lock/unlock patterns.


Add link-resolution logic that searches for a link in WORLD and/or Desktop (often SP\_APPLICATION and SP\_TOP\DESKTOP). Use FileReadLink / FileGetLinkExtraData or the desktop-info attribute (FEA\_DESKTOP\_INFO / DesktopInfo in Include/newdesk.def) to confirm a link points to the DISTAPPS target. Update the toggle state based on whether a link exists.


On toggle‑on, call FileCreateLink to create a link in the chosen target directory. Populate any required desktop metadata (FEA\_DESKTOP\_INFO) so GeoManager/desktop treats it as an executable. On toggle‑off, delete the link (FileDelete) and refresh the model state. Ensure product variation: if GPC\_DESKTOP\_LINKS\_IN\_INI is true, coordinate with the INI‑based link mechanism instead of (or in addition to) file links.


On module open, rescan DISTAPPS and re-evaluate link presence, rather than relying solely on cached state. If product policy requires, store/restore user selections in the Preferences file (Config library), but always reconcile with actual links in WORLD/DESKTOP to avoid drift.

Add a short README or comment block near the module describing: DISTAPPS source directory, link creation/removal behavior, and any product flags (e.g., GPC\_DESKTOP\_LINKS\_IN\_INI). Include references to Include/file.def and Include/newdesk.def for link/desktop info.



In detail:

Create the public/private headers for the preferences module and define the data model types (app entry record, link state enum, list context struct). Add constants for paths (DISTAPPS subdir) and any feature flags. Declare \_pascal function prototypes with C89-compliant signatures. Keep structs small; use handle-based storage where needed.


Create the .ui (or equivalent resource) with the list and toggles. Wire UI messages to empty handlers (e.g., “refresh list,” “toggle item”). Ensure object names and messages align with the header declarations from Phase 1. No real scanning or linking logic yet—just UI plumbing.

Implement the scan routine against SP\_SYS\_APPLICATION + DISTAPPS, build the in-memory model, and push names into the list UI. Use FileEnum and MemAlloc/MemLock/Unlock patterns. This phase should only read the file system (no link creation yet).


Add link detection logic to mark items as selected based on FileReadLink/FEA\_DESKTOP\_INFO. Refresh UI state based on detected links. Still no link creation/removal in this phase.


On toggle on/off, create or delete links in WORLD and/or Desktop as configured. Handle product settings like GPC\_DESKTOP\_LINKS\_IN\_INI. Update the model and UI state after each operation.


Ensure the module rechecks the file system on open and after link operations. Optionally persist last view state (not the link state) in the preferences file. Handle missing DISTAPPS directory gracefully.




