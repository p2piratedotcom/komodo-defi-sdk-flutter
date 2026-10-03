# P2Pirate desktop coin assets

The wallet downloads coin configuration and PNG artwork from
`p2piratedotcom/Assets` after the user accepts the first-run prompt or an update
in Settings. It verifies a commit-pinned snapshot before installing it in the
SDK catalog store. The SDK update manager does not automatically replace this
catalog with a remote version.

`AssetIcon.setRuntimeIconDirectory` selects the verified snapshot's icon
directory before the wallet UI starts. Registered custom images take priority,
then installed PNGs, then declared bundled images. Missing artwork renders a
local ticker badge without a network request.

The bundled configuration is still the reviewed Shoreline coin snapshot at
`98b29f5ea53a46a701e791a565a5fab7ee83b947`. Its commit is a record of the bundled
source, not a commit in the new Assets repository. It remains available when
the user skips the optional download. Build-time and automatic runtime fetches
are disabled; the GUI owns manual update consent and snapshot verification.
