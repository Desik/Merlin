local addonName, Merlin = ...
_G.Merlin = Merlin

local lsmCached
local lsmCallbackRegistered = false

local function GetLSM()
	if not lsmCached and LibStub then
		lsmCached = LibStub("LibSharedMedia-3.0", true)
	end
	if lsmCached and not lsmCallbackRegistered and lsmCached.RegisterCallback then
		lsmCallbackRegistered = true
		lsmCached.RegisterCallback(Merlin, "LibSharedMedia_Registered", function(_, mediatype, key)
			if mediatype == "font" and Merlin.db and Merlin.IsFontInUse(key) then
				Merlin.RequestRefresh()
			end
		end)
	end
	return lsmCached
end

local DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local classR, classG, classB

Merlin.defaults = {
	locked = true,
	windowOpacity = 0.94,
	navCollapsed = true,
	useMasque = true,
	hideTooltipInCombat = false,
	tooltipAnchor = "ANCHOR_BOTTOMLEFT",
	allowCancel = true,
	oocAlpha = 1.0,
	borderSize = 1,
	iconZoom = 0.08,
	warnThreshold = 30,
	urgentThreshold = 5,
	durationRounding = "NEAREST",
	colors = {
		buffBorder = { 0.12, 0.12, 0.12 },
		enchantBorder = { 0.65, 0.35, 0.95 },
		externalBorder = { 0.90, 0.72, 0.30 },
		timerWarn = { 1.0, 0.82, 0.25 },
		timerUrgent = { 1.0, 0.25, 0.25 },
		dispelNone = { 0.80, 0.12, 0.12 },
		dispelMagic = { 0.20, 0.60, 1.00 },
		dispelCurse = { 0.60, 0.20, 1.00 },
		dispelDisease = { 0.60, 0.40, 0.10 },
		dispelPoison = { 0.10, 0.70, 0.15 },
		dispelBleed = { 0.85, 0.15, 0.35 },
	},
	fontName = "Default",
	fontOutline = "OUTLINE",
	buffs = {
		enabled = true,
		size = 34,
		perRow = 12,
		maxIcons = 32,
		spacingX = 4,
		spacingY = 16,
		orientation = "HORIZONTAL",
		growthX = "LEFT",
		growthY = "DOWN",
		sortMethod = "DEFAULT",
		sortDirection = "NORMAL",
		fontName = "Default",
		fontOutline = "OUTLINE",
		showDuration = true,
		durationFormat = "SMART",
		showDecimals = false,
		colorDurationByTime = true,
		durationFontSize = 11,
		durationAnchor = "BELOW",
		durationOffsetX = 0,
		durationOffsetY = -2,
		showCount = true,
		countFontSize = 11,
		countAnchor = "TOPRIGHT",
		countOffsetX = -1,
		countOffsetY = -1,
		showCooldownSwipe = false,
		reverseCooldownSwipe = true,
		anchorTo = "SCREEN",
		x = -210,
		y = -20,
	},
	debuffs = {
		enabled = true,
		size = 38,
		perRow = 8,
		maxIcons = 16,
		spacingX = 4,
		spacingY = 16,
		orientation = "HORIZONTAL",
		growthX = "LEFT",
		growthY = "DOWN",
		sortMethod = "DEFAULT",
		sortDirection = "NORMAL",
		showDispelIcon = false,
		showDuration = true,
		durationFormat = "SMART",
		showDecimals = true,
		colorDurationByTime = true,
		durationFontSize = 12,
		durationAnchor = "BELOW",
		durationOffsetX = 0,
		durationOffsetY = -2,
		showCount = true,
		countFontSize = 12,
		countAnchor = "TOPRIGHT",
		countOffsetX = -1,
		countOffsetY = -1,
		showCooldownSwipe = false,
		reverseCooldownSwipe = true,
		anchorTo = "SCREEN",
		x = -210,
		y = -150,
	},
	externals = {
		enabled = true,
		size = 42,
		perRow = 4,
		maxIcons = 6,
		spacingX = 6,
		spacingY = 16,
		orientation = "HORIZONTAL",
		growthX = "LEFT",
		growthY = "DOWN",
		sortMethod = "DEFAULT",
		sortDirection = "NORMAL",
		fontName = "Default",
		fontOutline = "OUTLINE",
		showDuration = true,
		durationFormat = "SMART",
		showDecimals = true,
		colorDurationByTime = true,
		durationFontSize = 13,
		durationAnchor = "CENTER",
		durationOffsetX = 0,
		durationOffsetY = 0,
		showCount = true,
		countFontSize = 12,
		countAnchor = "BOTTOMRIGHT",
		countOffsetX = -1,
		countOffsetY = 1,
		showCooldownSwipe = true,
		reverseCooldownSwipe = true,
		anchorTo = "SCREEN",
		x = -210,
		y = -290,
	},
	enchants = {
		enabled = true,
		showWeaponEnchants = true,
		detachEnchants = false,
		enchantPlacement = "BEFORE",
		grouped = false,
		followBuffsStyle = true,
		useEnchantIcon = true,
		size = 36,
		perRow = 3,
		maxIcons = 3,
		spacingX = 4,
		spacingY = 14,
		orientation = "HORIZONTAL",
		growthX = "LEFT",
		growthY = "DOWN",
		sortMethod = "DEFAULT",
		sortDirection = "NORMAL",
		fontName = "Default",
		fontOutline = "OUTLINE",
		showDuration = true,
		durationFormat = "SMART",
		showDecimals = false,
		colorDurationByTime = true,
		durationFontSize = 11,
		durationAnchor = "BELOW",
		durationOffsetX = 0,
		durationOffsetY = -2,
		showCount = true,
		countFontSize = 11,
		countAnchor = "TOPRIGHT",
		countOffsetX = -1,
		countOffsetY = -1,
		showCooldownSwipe = false,
		reverseCooldownSwipe = true,
		anchorTo = "SCREEN",
		x = -210,
		y = -410,
		slots = {
			mh = { x = -210, y = -410 },
			oh = { x = -270, y = -410 },
			ranged = { x = -330, y = -410 },
		},
	},
}

local VALID_ORIENTATION = { HORIZONTAL = true, VERTICAL = true }
local VALID_GROWTH_X = { LEFT = true, RIGHT = true }
local VALID_GROWTH_Y = { DOWN = true, UP = true }
local VALID_SORT_METHOD = { DEFAULT = true, EXPIRATION = true, NAME = true, INDEX = true }
local VALID_SORT_DIR = { NORMAL = true, REVERSE = true }
local VALID_ENCHANT_PLACE = { BEFORE = true, AFTER = true }
local VALID_OUTLINE = { [""] = true, OUTLINE = true, THICKOUTLINE = true }
local VALID_DURATION_FMT = {
	SMART = true,
	COMPACT = true,
	DETAILED = true,
	CLOCK = true,
	DECIMAL = true,
	BLIZZARD = true,
}
local VALID_DURATION_ROUND = { NEAREST = true, CEIL90 = true, UP = true }
local VALID_DURATION_ANCHOR = { BELOW = true, BOTTOM = true, CENTER = true, TOP = true, ABOVE = true }
local VALID_COUNT_ANCHOR = { TOPRIGHT = true, BOTTOMRIGHT = true, TOPLEFT = true, BOTTOMLEFT = true, CENTER = true }
local VALID_ANCHOR_TO = { SCREEN = true, MINIMAP = true, BUFFS = true }
local VALID_TOOLTIP_ANCHOR = {
	ANCHOR_BOTTOMLEFT = true,
	ANCHOR_TOPLEFT = true,
	ANCHOR_BOTTOMRIGHT = true,
	ANCHOR_CURSOR = true,
}

local VALID_SCOPE = { DEFAULT = true, ROLE = true, CLASS = true }

local GROUP_BOOL_KEYS = {
	"enabled", "showDuration", "showDecimals", "colorDurationByTime",
	"showCount", "showCooldownSwipe", "reverseCooldownSwipe",
}
local GLOBAL_BOOL_KEYS = { "locked", "navCollapsed", "useMasque", "hideTooltipInCombat", "allowCancel" }
local LEGACY_ENCHANT_KEYS = { "showWeaponEnchants", "detachEnchants", "enchantPlacement" }

local AURA_RESTRICTIONS = { "Combat", "Encounter", "PvPMatch" }

function Merlin.IsRestricted()
	if InCombatLockdown() then
		return true
	end
	local types = Enum and Enum.AddOnRestrictionType
	local isActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
	if not (types and isActive) then
		return false
	end
	for _, name in ipairs(AURA_RESTRICTIONS) do
		local t = types[name]
		if t ~= nil then
			local ok, active = pcall(isActive, t)
			if ok and active == true then
				return true
			end
		end
	end
	return false
end

local function ClampNumber(value, default, low, high)
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.max(low, math.min(high, value))
end

local function ValidateEnum(value, valid, default)
	if type(value) == "string" and valid[value] then
		return value
	end
	return default
end

local function SanitizeColor(saved, def)
	if type(saved) ~= "table" then
		return { def[1], def[2], def[3] }
	end
	return {
		ClampNumber(saved[1], def[1], 0, 1),
		ClampNumber(saved[2], def[2], 0, 1),
		ClampNumber(saved[3], def[3], 0, 1),
	}
end

-- Pre-1.x profiles stored one global font; groups without their own inherit it once.
local legacyFontName, legacyFontOutline

local function SanitizeGroup(saved, def, isBuff)
	if type(saved) ~= "table" then
		saved = {}
	end
	if type(saved.fontName) ~= "string" or saved.fontName == "" then
		saved.fontName = legacyFontName or def.fontName
	end
	saved.fontOutline = ValidateEnum(saved.fontOutline, VALID_OUTLINE, legacyFontOutline or def.fontOutline)
	for _, key in ipairs(GROUP_BOOL_KEYS) do
		if type(saved[key]) ~= "boolean" then
			saved[key] = def[key]
		end
	end
	if def.showDispelIcon ~= nil and type(saved.showDispelIcon) ~= "boolean" then
		saved.showDispelIcon = def.showDispelIcon
	end
	saved.aspect = nil
	saved.size = math.floor(ClampNumber(saved.size, def.size, 18, 64) + 0.5)
	saved.perRow = math.floor(ClampNumber(saved.perRow, def.perRow, 1, 32) + 0.5)
	saved.maxIcons = math.floor(ClampNumber(saved.maxIcons, def.maxIcons, 1, 40) + 0.5)
	saved.spacingX = math.floor(ClampNumber(saved.spacingX, def.spacingX, 0, 32) + 0.5)
	saved.spacingY = math.floor(ClampNumber(saved.spacingY, def.spacingY, 0, 32) + 0.5)
	saved.orientation = ValidateEnum(saved.orientation, VALID_ORIENTATION, def.orientation)
	saved.growthX = ValidateEnum(saved.growthX, VALID_GROWTH_X, def.growthX)
	saved.growthY = ValidateEnum(saved.growthY, VALID_GROWTH_Y, def.growthY)
	saved.sortMethod = ValidateEnum(saved.sortMethod, VALID_SORT_METHOD, def.sortMethod)
	saved.sortDirection = ValidateEnum(saved.sortDirection, VALID_SORT_DIR, def.sortDirection)
	saved.durationFormat = ValidateEnum(saved.durationFormat, VALID_DURATION_FMT, def.durationFormat)
	saved.durationFontSize = math.floor(ClampNumber(saved.durationFontSize, def.durationFontSize, 8, 24) + 0.5)
	saved.durationAnchor = ValidateEnum(saved.durationAnchor, VALID_DURATION_ANCHOR, def.durationAnchor)
	saved.durationOffsetX = math.floor(ClampNumber(saved.durationOffsetX, def.durationOffsetX, -32, 32) + 0.5)
	saved.durationOffsetY = math.floor(ClampNumber(saved.durationOffsetY, def.durationOffsetY, -32, 32) + 0.5)
	saved.countFontSize = math.floor(ClampNumber(saved.countFontSize, def.countFontSize, 8, 24) + 0.5)
	saved.countAnchor = ValidateEnum(saved.countAnchor, VALID_COUNT_ANCHOR, def.countAnchor)
	saved.countOffsetX = math.floor(ClampNumber(saved.countOffsetX, def.countOffsetX, -32, 32) + 0.5)
	saved.countOffsetY = math.floor(ClampNumber(saved.countOffsetY, def.countOffsetY, -32, 32) + 0.5)
	saved.anchorTo = ValidateEnum(saved.anchorTo, VALID_ANCHOR_TO, def.anchorTo)
	if isBuff and saved.anchorTo == "BUFFS" then
		saved.anchorTo = "SCREEN"
	end
	saved.x = math.floor(ClampNumber(saved.x, def.x, -5000, 5000) + 0.5)
	saved.y = math.floor(ClampNumber(saved.y, def.y, -5000, 5000) + 0.5)
	if def.slots then
		saved.enabled = true
		if type(saved.showWeaponEnchants) ~= "boolean" then
			saved.showWeaponEnchants = def.showWeaponEnchants
		end
		if type(saved.detachEnchants) ~= "boolean" then
			saved.detachEnchants = def.detachEnchants
		end
		saved.enchantPlacement = ValidateEnum(saved.enchantPlacement, VALID_ENCHANT_PLACE, def.enchantPlacement)
		if type(saved.grouped) ~= "boolean" then
			saved.grouped = def.grouped
		end
		if type(saved.followBuffsStyle) ~= "boolean" then
			saved.followBuffsStyle = def.followBuffsStyle
		end
		if type(saved.useEnchantIcon) ~= "boolean" then
			saved.useEnchantIcon = def.useEnchantIcon
		end
		if type(saved.slots) ~= "table" then
			saved.slots = {}
		end
		for slotKey, slotDef in pairs(def.slots) do
			if type(saved.slots[slotKey]) ~= "table" then
				saved.slots[slotKey] = {}
			end
			saved.slots[slotKey].x = math.floor(ClampNumber(saved.slots[slotKey].x, slotDef.x, -5000, 5000) + 0.5)
			saved.slots[slotKey].y = math.floor(ClampNumber(saved.slots[slotKey].y, slotDef.y, -5000, 5000) + 0.5)
		end
	end
	return saved
end

local GROUP_KEYS = { buffs = true, debuffs = true, externals = true, enchants = true }
local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local activeGroupTables = {}
local activeGroupScopes = {}

local function DeepCopy(src)
	if type(src) ~= "table" then
		return src
	end
	local copy = {}
	for k, v in pairs(src) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

function Merlin.GetPlayerClassInfo()
	local localized, file = UnitClass("player")
	return file or "UNKNOWN", localized or file or "Class"
end

function Merlin.GetPlayerRoleInfo()
	local role
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
		local spec = C_SpecializationInfo.GetSpecialization()
		if spec then
			role = select(5, C_SpecializationInfo.GetSpecializationInfo(spec))
		end
	end
	if (not role or role == "NONE") and UnitGroupRolesAssigned then
		local assigned = UnitGroupRolesAssigned("player")
		if assigned and assigned ~= "NONE" then
			role = assigned
		end
	end
	if not ROLE_LABELS[role] then
		role = "DAMAGER"
	end
	return role, ROLE_LABELS[role]
end

local function GetScopeBucketKey()
	local classKey = Merlin.GetPlayerClassInfo()
	local roleKey = Merlin.GetPlayerRoleInfo()
	return classKey .. ":" .. roleKey
end

local function SanitizeOverrideBucket(bucket)
	if type(bucket) ~= "table" then
		return nil
	end
	local cleaned = {}
	local hasAny = false
	for key, val in pairs(bucket) do
		if GROUP_KEYS[key] and type(val) == "table" then
			cleaned[key] = SanitizeGroup(val, Merlin.defaults[key], key == "buffs")
			hasAny = true
		end
	end
	return hasAny and cleaned or nil
end

local function SanitizeOverridesAndScopes(db)
	if type(db.overrides) ~= "table" then
		db.overrides = {}
	end
	local cleanClass = {}
	if type(db.overrides.class) == "table" then
		for classKey, bucket in pairs(db.overrides.class) do
			if type(classKey) == "string" and classKey:match("^[A-Z]+$") then
				local cleaned = SanitizeOverrideBucket(bucket)
				if cleaned then
					cleanClass[classKey] = cleaned
				end
			end
		end
	end
	local cleanRole = {}
	if type(db.overrides.role) == "table" then
		for roleKey, bucket in pairs(db.overrides.role) do
			if ROLE_LABELS[roleKey] then
				local cleaned = SanitizeOverrideBucket(bucket)
				if cleaned then
					cleanRole[roleKey] = cleaned
				end
			end
		end
	end
	db.overrides = { class = cleanClass, role = cleanRole }

	local cleanChoices = {}
	if type(db.scopeChoices) == "table" then
		for scopeKey, choices in pairs(db.scopeChoices) do
			if type(scopeKey) == "string" and scopeKey:match("^[A-Z]+:[A-Z]+$") and type(choices) == "table" then
				local cleaned = {}
				local hasAny = false
				for cfgKey, scope in pairs(choices) do
					if GROUP_KEYS[cfgKey] and VALID_SCOPE[scope] then
						cleaned[cfgKey] = scope
						hasAny = true
					end
				end
				if hasAny then
					cleanChoices[scopeKey] = cleaned
				end
			end
		end
	end
	db.scopeChoices = cleanChoices
end

function Merlin.ResolveGroupScopes()
	if type(MerlinDB) ~= "table" then
		return false
	end
	if type(MerlinDB.overrides) ~= "table" then
		MerlinDB.overrides = {}
	end
	if type(MerlinDB.overrides.class) ~= "table" then
		MerlinDB.overrides.class = {}
	end
	if type(MerlinDB.overrides.role) ~= "table" then
		MerlinDB.overrides.role = {}
	end
	if type(MerlinDB.scopeChoices) ~= "table" then
		MerlinDB.scopeChoices = {}
	end

	local classKey = Merlin.GetPlayerClassInfo()
	local roleKey = Merlin.GetPlayerRoleInfo()
	local scopeKey = classKey .. ":" .. roleKey
	local classBucket = MerlinDB.overrides.class[classKey]
	local roleBucket = MerlinDB.overrides.role[roleKey]
	local choices = MerlinDB.scopeChoices[scopeKey]
	local changed = false

	for key in pairs(GROUP_KEYS) do
		local def = Merlin.defaults[key]
		local isBuff = (key == "buffs")
		local preferred = choices and choices[key]
		local nextTable, nextScope

		if preferred == "DEFAULT" then
			nextTable = MerlinDB[key]
			nextScope = "DEFAULT"
		elseif preferred == "CLASS" and classBucket and type(classBucket[key]) == "table" then
			classBucket[key] = SanitizeGroup(classBucket[key], def, isBuff)
			nextTable = classBucket[key]
			nextScope = "CLASS"
		elseif preferred == "ROLE" and roleBucket and type(roleBucket[key]) == "table" then
			roleBucket[key] = SanitizeGroup(roleBucket[key], def, isBuff)
			nextTable = roleBucket[key]
			nextScope = "ROLE"
		elseif classBucket and type(classBucket[key]) == "table" then
			classBucket[key] = SanitizeGroup(classBucket[key], def, isBuff)
			nextTable = classBucket[key]
			nextScope = "CLASS"
		elseif roleBucket and type(roleBucket[key]) == "table" then
			roleBucket[key] = SanitizeGroup(roleBucket[key], def, isBuff)
			nextTable = roleBucket[key]
			nextScope = "ROLE"
		else
			nextTable = MerlinDB[key]
			nextScope = "DEFAULT"
		end

		if activeGroupTables[key] ~= nextTable or activeGroupScopes[key] ~= nextScope then
			changed = true
		end
		activeGroupTables[key] = nextTable
		activeGroupScopes[key] = nextScope
	end
	return changed
end

function Merlin.GetGroupScope(cfgKey)
	return activeGroupScopes[cfgKey] or "DEFAULT"
end

function Merlin.SetGroupScope(cfgKey, scope)
	if Merlin.IsRestricted() or not GROUP_KEYS[cfgKey] or type(MerlinDB) ~= "table" then
		return
	end
	if not VALID_SCOPE[scope] then
		scope = "DEFAULT"
	end
	if type(MerlinDB.overrides) ~= "table" then
		MerlinDB.overrides = {}
	end
	if type(MerlinDB.overrides.class) ~= "table" then
		MerlinDB.overrides.class = {}
	end
	if type(MerlinDB.overrides.role) ~= "table" then
		MerlinDB.overrides.role = {}
	end
	if type(MerlinDB.scopeChoices) ~= "table" then
		MerlinDB.scopeChoices = {}
	end

	local classKey = Merlin.GetPlayerClassInfo()
	local roleKey = Merlin.GetPlayerRoleInfo()
	local scopeKey = classKey .. ":" .. roleKey
	local current = activeGroupTables[cfgKey] or MerlinDB[cfgKey]

	if scope == "CLASS" then
		MerlinDB.overrides.class[classKey] = MerlinDB.overrides.class[classKey] or {}
		if type(MerlinDB.overrides.class[classKey][cfgKey]) ~= "table" then
			MerlinDB.overrides.class[classKey][cfgKey] = DeepCopy(current)
		end
	elseif scope == "ROLE" then
		MerlinDB.overrides.role[roleKey] = MerlinDB.overrides.role[roleKey] or {}
		if type(MerlinDB.overrides.role[roleKey][cfgKey]) ~= "table" then
			MerlinDB.overrides.role[roleKey][cfgKey] = DeepCopy(current)
		end
	end

	MerlinDB.scopeChoices[scopeKey] = MerlinDB.scopeChoices[scopeKey] or {}
	MerlinDB.scopeChoices[scopeKey][cfgKey] = scope

	Merlin.ResolveGroupScopes()
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
end

function Merlin.CopyGroupFromDefault(cfgKey)
	if Merlin.IsRestricted() or not GROUP_KEYS[cfgKey] or type(MerlinDB) ~= "table" then
		return
	end
	local scope = Merlin.GetGroupScope(cfgKey)
	if scope == "DEFAULT" then
		return
	end
	local copy = DeepCopy(MerlinDB[cfgKey])
	if scope == "CLASS" then
		local classKey = Merlin.GetPlayerClassInfo()
		MerlinDB.overrides.class[classKey] = MerlinDB.overrides.class[classKey] or {}
		MerlinDB.overrides.class[classKey][cfgKey] = copy
	elseif scope == "ROLE" then
		local roleKey = Merlin.GetPlayerRoleInfo()
		MerlinDB.overrides.role[roleKey] = MerlinDB.overrides.role[roleKey] or {}
		MerlinDB.overrides.role[roleKey][cfgKey] = copy
	end
	Merlin.ResolveGroupScopes()
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
end

function Merlin.ClearCurrentOverrides()
	if Merlin.IsRestricted() or type(MerlinDB) ~= "table" or type(MerlinDB.overrides) ~= "table" then
		return
	end
	local classKey = Merlin.GetPlayerClassInfo()
	local roleKey = Merlin.GetPlayerRoleInfo()
	if MerlinDB.overrides.class then
		MerlinDB.overrides.class[classKey] = nil
	end
	if MerlinDB.overrides.role then
		MerlinDB.overrides.role[roleKey] = nil
	end
	if type(MerlinDB.scopeChoices) == "table" then
		MerlinDB.scopeChoices[GetScopeBucketKey()] = nil
	end
	Merlin.ResolveGroupScopes()
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
end

local InitializeDatabase

local EXPORT_PREFIX = "!MERLIN1!"
local EXPORT_GLOBAL_KEYS = {
	"windowOpacity", "useMasque", "hideTooltipInCombat", "tooltipAnchor",
	"allowCancel", "oocAlpha", "borderSize", "iconZoom",
	"warnThreshold", "urgentThreshold", "durationRounding", "colors", "fontName", "fontOutline",
}
local GROUP_ORDER = { "buffs", "debuffs", "externals", "enchants" }

function Merlin.ExportProfile(target)
	if not (C_EncodingUtil and C_EncodingUtil.SerializeJSON
		and C_EncodingUtil.CompressString and C_EncodingUtil.EncodeBase64) then
		return nil, "Encoding API unavailable."
	end
	target = target or "FULL"
	local payload = { v = 1, target = target, groups = {} }
	local db = MerlinDB

	if target == "FULL" or target == "DEFAULT" then
		payload.global = {}
		for _, k in ipairs(EXPORT_GLOBAL_KEYS) do
			if db[k] ~= nil then
				payload.global[k] = DeepCopy(db[k])
			end
		end
		for _, g in ipairs(GROUP_ORDER) do
			payload.groups[g] = DeepCopy(db[g])
		end
		if target == "FULL" and type(db.overrides) == "table" then
			payload.overrides = DeepCopy(db.overrides)
		end
		if target == "FULL" and type(db.scopeChoices) == "table" then
			payload.scopeChoices = DeepCopy(db.scopeChoices)
		end
	elseif target == "ROLE" then
		local role = Merlin.GetPlayerRoleInfo()
		local bucket = type(db.overrides) == "table" and type(db.overrides.role) == "table" and db.overrides.role[role]
		for _, g in ipairs(GROUP_ORDER) do
			payload.groups[g] = DeepCopy((bucket and bucket[g]) or db[g])
		end
	elseif target == "CLASS" then
		local classFile = Merlin.GetPlayerClassInfo()
		local bucket = type(db.overrides) == "table" and type(db.overrides.class) == "table" and db.overrides.class[classFile]
		for _, g in ipairs(GROUP_ORDER) do
			payload.groups[g] = DeepCopy((bucket and bucket[g]) or db[g])
		end
	else
		return nil, "Unknown export target."
	end

	local ok, encoded = pcall(function()
		local json = C_EncodingUtil.SerializeJSON(payload)
		local compressed = C_EncodingUtil.CompressString(json)
		return EXPORT_PREFIX .. C_EncodingUtil.EncodeBase64(compressed)
	end)
	if not ok or type(encoded) ~= "string" then
		return nil, "Failed to encode profile."
	end
	return encoded
end

function Merlin.ImportProfile(str, target)
	if Merlin.IsRestricted() then
		return false, "Cannot import in combat or restricted instance."
	end
	if not (C_EncodingUtil and C_EncodingUtil.DecodeBase64
		and C_EncodingUtil.DecompressString and C_EncodingUtil.DeserializeJSON) then
		return false, "Encoding API unavailable."
	end
	if type(str) ~= "string" then
		return false, "Paste a Merlin profile string."
	end
	local trimmed = str:match("^%s*(.-)%s*$")
	if trimmed:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return false, "Invalid profile string (missing !MERLIN1! header)."
	end
	local body = trimmed:sub(#EXPORT_PREFIX + 1):gsub("%s+", "")
	if body == "" then
		return false, "Empty profile string."
	end

	local ok, payload = pcall(function()
		local compressed = C_EncodingUtil.DecodeBase64(body)
		local json = C_EncodingUtil.DecompressString(compressed)
		return C_EncodingUtil.DeserializeJSON(json)
	end)
	if not ok or type(payload) ~= "table" or payload.v ~= 1 or type(payload.groups) ~= "table" then
		return false, "Corrupted or unsupported profile string."
	end

	target = target or "FULL"
	if target == "FULL" then
		local keepLocked = MerlinDB and MerlinDB.locked
		local keepNav = MerlinDB and MerlinDB.navCollapsed
		local fresh = { locked = keepLocked, navCollapsed = keepNav }
		if type(payload.global) == "table" then
			for _, k in ipairs(EXPORT_GLOBAL_KEYS) do
				if payload.global[k] ~= nil then
					fresh[k] = DeepCopy(payload.global[k])
				end
			end
		end
		for _, g in ipairs(GROUP_ORDER) do
			if type(payload.groups[g]) == "table" then
				fresh[g] = DeepCopy(payload.groups[g])
			end
		end
		if type(payload.overrides) == "table" then
			fresh.overrides = DeepCopy(payload.overrides)
		end
		if type(payload.scopeChoices) == "table" then
			fresh.scopeChoices = DeepCopy(payload.scopeChoices)
		end
		MerlinDB = fresh
		InitializeDatabase()
	elseif target == "DEFAULT" then
		if type(payload.global) == "table" then
			for _, k in ipairs(EXPORT_GLOBAL_KEYS) do
				if payload.global[k] ~= nil then
					MerlinDB[k] = DeepCopy(payload.global[k])
				end
			end
		end
		for _, g in ipairs(GROUP_ORDER) do
			if type(payload.groups[g]) == "table" then
				MerlinDB[g] = DeepCopy(payload.groups[g])
			end
		end
		InitializeDatabase()
	elseif target == "ROLE" then
		local role = Merlin.GetPlayerRoleInfo()
		if type(MerlinDB.overrides) ~= "table" then
			MerlinDB.overrides = {}
		end
		if type(MerlinDB.overrides.role) ~= "table" then
			MerlinDB.overrides.role = {}
		end
		local bucket = {}
		for _, g in ipairs(GROUP_ORDER) do
			if type(payload.groups[g]) == "table" then
				bucket[g] = SanitizeGroup(DeepCopy(payload.groups[g]), Merlin.defaults[g], g == "buffs")
			end
		end
		MerlinDB.overrides.role[role] = bucket
		Merlin.ResolveGroupScopes()
	elseif target == "CLASS" then
		local classFile = Merlin.GetPlayerClassInfo()
		if type(MerlinDB.overrides) ~= "table" then
			MerlinDB.overrides = {}
		end
		if type(MerlinDB.overrides.class) ~= "table" then
			MerlinDB.overrides.class = {}
		end
		local bucket = {}
		for _, g in ipairs(GROUP_ORDER) do
			if type(payload.groups[g]) == "table" then
				bucket[g] = SanitizeGroup(DeepCopy(payload.groups[g]), Merlin.defaults[g], g == "buffs")
			end
		end
		MerlinDB.overrides.class[classFile] = bucket
		Merlin.ResolveGroupScopes()
	else
		return false, "Unknown import target."
	end

	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
	return true
end

function Merlin.ResetProfile()
	if Merlin.IsRestricted() then
		Merlin.Print("Cannot reset profile in combat or restricted instance.")
		return
	end
	MerlinDB = {}
	InitializeDatabase()
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
end

InitializeDatabase = function()
	if type(MerlinDB) ~= "table" then
		MerlinDB = {}
	end
	local db = MerlinDB
	local def = Merlin.defaults

	for _, key in ipairs(GLOBAL_BOOL_KEYS) do
		if type(db[key]) ~= "boolean" then
			db[key] = def[key]
		end
	end
	db.windowOpacity = ClampNumber(db.windowOpacity, def.windowOpacity, 0.5, 1.0)
	db.oocAlpha = ClampNumber(db.oocAlpha, def.oocAlpha, 0.0, 1.0)
	db.borderSize = math.floor(ClampNumber(db.borderSize, def.borderSize, 0, 3) + 0.5)
	db.iconZoom = ClampNumber(db.iconZoom, def.iconZoom, 0.0, 0.15)
	db.warnThreshold = math.floor(ClampNumber(db.warnThreshold, def.warnThreshold, 5, 60) + 0.5)
	db.urgentThreshold = math.floor(ClampNumber(db.urgentThreshold, def.urgentThreshold, 1, 15) + 0.5)
	db.durationRounding = ValidateEnum(db.durationRounding, VALID_DURATION_ROUND, def.durationRounding)
	db.tooltipAnchor = ValidateEnum(db.tooltipAnchor, VALID_TOOLTIP_ANCHOR, def.tooltipAnchor)

	if type(db.colors) ~= "table" then
		db.colors = {}
	end
	for key, colorDef in pairs(def.colors) do
		db.colors[key] = SanitizeColor(db.colors[key], colorDef)
	end

	if type(db.fontName) ~= "string" or db.fontName == "" then
		db.fontName = def.fontName
	end
	db.fontOutline = ValidateEnum(db.fontOutline, VALID_OUTLINE, def.fontOutline)
	legacyFontName, legacyFontOutline = db.fontName, db.fontOutline

	-- Migrate legacy enchant toggles from buffs -> enchants if present
	if type(db.buffs) == "table" then
		if type(db.enchants) ~= "table" then
			db.enchants = {}
		end
		for _, k in ipairs(LEGACY_ENCHANT_KEYS) do
			if db.buffs[k] ~= nil and db.enchants[k] == nil then
				db.enchants[k] = db.buffs[k]
			end
			db.buffs[k] = nil
		end
	end

	db.buffs = SanitizeGroup(db.buffs, def.buffs, true)
	db.debuffs = SanitizeGroup(db.debuffs, def.debuffs, false)
	db.externals = SanitizeGroup(db.externals, def.externals, false)
	db.enchants = SanitizeGroup(db.enchants, def.enchants, false)

	SanitizeOverridesAndScopes(db)

	-- Proxy Merlin.db so group keys transparently route to the active scope (Class -> Role -> Default)
	Merlin.db = setmetatable({}, {
		__index = function(_, key)
			if GROUP_KEYS[key] then
				return activeGroupTables[key] or db[key]
			end
			return db[key]
		end,
		__newindex = function(_, key, value)
			if GROUP_KEYS[key] then
				activeGroupTables[key] = value
			else
				db[key] = value
			end
		end,
	})
	Merlin.ResolveGroupScopes()
end

function Merlin.GetIconDimensions(cfg)
	return cfg.size, cfg.size
end

function Merlin.GetClassColor()
	if not classR then
		local _, class = UnitClass("player")
		local color = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		if color then
			classR, classG, classB = color:GetRGB()
		else
			classR, classG, classB = 0.4, 0.65, 0.8
		end
	end
	return classR, classG, classB
end

-- Soft, desaturated class tint matching Vigil's subtle accent weight.
function Merlin.GetMutedClassColor()
	local r, g, b = Merlin.GetClassColor()
	local mix = 0.42
	local base = 0.76
	return base + (r - base) * mix, base + (g - base) * mix, base + (b - base) * mix
end

function Merlin.GetFontPath(name)
	name = type(name) == "string" and name or "Default"
	local LSM = GetLSM()
	if name ~= "Default" and LSM then
		local path = LSM:Fetch("font", name, true)
		if path then
			return path
		end
	end
	return DEFAULT_FONT
end

-- Returns the style config for detached enchants (Buffs when followBuffsStyle is on).
function Merlin.GetEnchantStyleConfig()
	if Merlin.db.enchants.followBuffsStyle then
		return Merlin.db.buffs
	end
	return Merlin.db.enchants
end

function Merlin.IsFontInUse(key)
	for groupKey in pairs(GROUP_KEYS) do
		local cfg = Merlin.db[groupKey]
		if type(cfg) == "table" and cfg.fontName == key then
			return true
		end
	end
	return false
end

function Merlin.GetFontOptions()
	local list = { { label = "Default", store = "Default" } }
	local LSM = GetLSM()
	if LSM and LSM.List then
		local names = LSM:List("font")
		if type(names) == "table" then
			for _, name in ipairs(names) do
				if name ~= "Default" then
					list[#list + 1] = { label = name, store = name }
				end
			end
		end
	end
	return list
end

function Merlin.GetPixelSize(region)
	if PixelUtil and PixelUtil.ConvertPixelsToUIForRegion then
		return PixelUtil.ConvertPixelsToUIForRegion(1, region or UIParent)
	end
	return 1
end

function Merlin.CanAccessObject(obj)
	if not obj then
		return false
	end
	if obj.CanBeAccessedInContext then
		local allowed = obj:CanBeAccessedInContext()
		if (canaccessvalue and not canaccessvalue(allowed)) or allowed ~= true then
			return false
		end
	end
	if obj.IsForbidden and obj:IsForbidden() then
		return false
	end
	if canaccessvalue and not canaccessvalue(obj) then
		return false
	end
	if canaccesstable and not canaccesstable(obj) then
		return false
	end
	return true
end

function Merlin.Print(msg)
	local text = "|cffffd14dMerlin:|r " .. tostring(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(text)
	end
end

-- Deferred layout/refresh queue (combat-safe)
local refreshCallbacks = {}
local refreshScheduled = false
local refreshPending = false

function Merlin.RegisterRefresh(fn)
	refreshCallbacks[#refreshCallbacks + 1] = fn
end

local function RunRefresh()
	refreshScheduled = false
	if Merlin.IsRestricted() then
		refreshPending = true
		return
	end
	refreshPending = false
	for _, fn in ipairs(refreshCallbacks) do
		fn()
	end
end

function Merlin.RequestRefresh()
	if not Merlin.initialized then
		return
	end
	if Merlin.IsRestricted() then
		refreshPending = true
		return
	end
	if refreshScheduled then
		return
	end
	refreshScheduled = true
	C_Timer.After(0, RunRefresh)
end

function Merlin.ResetGroupPosition(cfgKey)
	if Merlin.IsRestricted() then
		Merlin.Print("Cannot reset position in combat or restricted instance.")
		return
	end
	local def = Merlin.defaults[cfgKey]
	if not def then
		return
	end
	Merlin.db[cfgKey].anchorTo = def.anchorTo
	Merlin.db[cfgKey].x = def.x
	Merlin.db[cfgKey].y = def.y
	if def.slots and Merlin.db[cfgKey].slots then
		for slotKey, slotDef in pairs(def.slots) do
			Merlin.db[cfgKey].slots[slotKey].x = slotDef.x
			Merlin.db[cfgKey].slots[slotKey].y = slotDef.y
		end
	end
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
end

function Merlin.ResetPositions()
	if Merlin.IsRestricted() then
		Merlin.Print("Cannot reset positions in combat or restricted instance.")
		return
	end
	for _, key in ipairs({ "buffs", "debuffs", "externals", "enchants" }) do
		local def = Merlin.defaults[key]
		Merlin.db[key].anchorTo = def.anchorTo
		Merlin.db[key].x = def.x
		Merlin.db[key].y = def.y
		if def.slots and Merlin.db[key].slots then
			for slotKey, slotDef in pairs(def.slots) do
				Merlin.db[key].slots[slotKey].x = slotDef.x
				Merlin.db[key].slots[slotKey].y = slotDef.y
			end
		end
	end
	Merlin.RequestRefresh()
	if Merlin.RefreshOptions then
		Merlin.RefreshOptions()
	end
	Merlin.Print("Positions reset to defaults.")
end

-- Slash command: /merlin
SLASH_MERLIN1 = "/merlin"
SlashCmdList.MERLIN = function(input)
	local cmd = (input or ""):match("^%s*(%S*)"):lower()
	if cmd == "" or cmd == "config" or cmd == "options" then
		if Merlin.ToggleOptions then
			Merlin.ToggleOptions()
		end
	elseif cmd == "unlock" or cmd == "move" then
		if Merlin.IsRestricted() then
			Merlin.Print("Cannot unlock movers in combat or restricted instance.")
			return
		end
		Merlin.db.locked = false
		Merlin.RequestRefresh()
		if Merlin.RefreshOptions then
			Merlin.RefreshOptions()
		end
		Merlin.Print("Movers unlocked. Drag to position, then /merlin lock.")
	elseif cmd == "lock" then
		Merlin.db.locked = true
		Merlin.RequestRefresh()
		if Merlin.RefreshOptions then
			Merlin.RefreshOptions()
		end
		Merlin.Print("Movers locked.")
	elseif cmd == "reset" then
		Merlin.ResetPositions()
	else
		Merlin.Print("/merlin — toggle options | unlock | lock | reset")
	end
end

-- Event lifecycle
local RUNTIME_EVENTS = {
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"UI_SCALE_CHANGED",
	"DISPLAY_SIZE_CHANGED",
	"PLAYER_ROLES_ASSIGNED",
	"PLAYER_ENTERING_WORLD",
	"WEAPON_ENCHANT_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED",
}

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then
			return
		end
		InitializeDatabase()
		events:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		if not Merlin.db then
			InitializeDatabase()
		else
			Merlin.ResolveGroupScopes()
		end
		GetLSM()
		if Merlin.SuppressBlizzardAuras then
			Merlin.SuppressBlizzardAuras()
		end
		if Merlin.InitStyle then
			Merlin.InitStyle()
		end
		if Merlin.InitContainers then
			Merlin.InitContainers()
		end
		for _, ev in ipairs(RUNTIME_EVENTS) do
			events:RegisterEvent(ev)
		end
		pcall(events.RegisterEvent, events, "ADDON_RESTRICTION_STATE_CHANGED")
		events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
		events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
		Merlin.initialized = true
		Merlin.RequestRefresh()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if Merlin.UpdateCombatAlpha then
			Merlin.UpdateCombatAlpha(true)
		end
		if Merlin.db and not Merlin.db.locked then
			Merlin.db.locked = true
			if Merlin.UpdateMovers then
				Merlin.UpdateMovers()
			end
		end
		if Merlin.CloseOptions then
			Merlin.CloseOptions()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if Merlin.UpdateCombatAlpha then
			Merlin.UpdateCombatAlpha(false)
		end
		if Merlin.ReapplyBlizzardSuppression then
			Merlin.ReapplyBlizzardSuppression()
		end
		if Merlin.RefreshEnchantIcons then
			Merlin.RefreshEnchantIcons()
		end
		if refreshPending and not Merlin.IsRestricted() then
			Merlin.RequestRefresh()
		end
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		Merlin.RequestRefresh()
	elseif event == "PLAYER_ENTERING_WORLD"
		or event == "WEAPON_ENCHANT_CHANGED"
		or event == "PLAYER_EQUIPMENT_CHANGED"
		or (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player")
	then
		if Merlin.RefreshEnchantIcons then
			Merlin.RefreshEnchantIcons()
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" then
		if Merlin.ResolveGroupScopes() then
			Merlin.RequestRefresh()
		end
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		C_Timer.After(0, function()
			if Merlin.IsRestricted() then
				if Merlin.db and not Merlin.db.locked then
					Merlin.db.locked = true
					if Merlin.UpdateMovers then
						Merlin.UpdateMovers()
					end
				end
				if Merlin.CloseOptions then
					Merlin.CloseOptions()
				end
			else
				if Merlin.MarkMasqueDirty then
					Merlin.MarkMasqueDirty()
				end
				if Merlin.RefreshEnchantIcons then
					Merlin.RefreshEnchantIcons()
				end
				if Merlin.ReapplyBlizzardSuppression then
					Merlin.ReapplyBlizzardSuppression()
				end
				Merlin.RequestRefresh()
			end
		end)
	end
end)
