--imports
local WIM = WIM;

--set namespace
setfenv(1, WIM);

-- Build identifier for installed-copy verification: the packaging
-- script stamps the shipped archive's copy with the source commit,
-- so diagnostics can state which build produced them. "dev" means
-- the addon is running straight from the source tree.
FORK_BUILD = "dev";
