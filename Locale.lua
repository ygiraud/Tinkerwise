-- Localization table. Keys are the English strings, which also serve as the fallback
-- for any client language without a translation in Locales/.

local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })
