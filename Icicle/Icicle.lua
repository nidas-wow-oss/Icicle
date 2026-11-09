Icicle = LibStub("AceAddon-3.0"):NewAddon("Icicle", "AceEvent-3.0","AceConsole-3.0","AceTimer-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local self , Icicle = Icicle , Icicle
local Icicle_TEXT="|cffffffffIcicle|r |cff00ff00Enhanced|r"
local Icicle_VERSION= " r335.01"
local Icicle_AUTHOR=" updated by |cff0070DENidhaus|r - Wowaura.com"
local Icicledb
-- HoJ dynamic cooldown detection
local hojSpellID = 10308
local hojLastCast = {}        -- [unitName] = GetTime()
local hojDetectedCD = {}      -- [unitName] = 40 or 60


function Icicle:OnInitialize()
self.db2 = LibStub("AceDB-3.0"):New("Icicledb",dbDefaults, "Default");
	--LibStub("AceConfig-3.0"):RegisterOptionsTable("Icicle", Icicle.Options, {"Icicle", "SS"})
	self:RegisterChatCommand("Icicle", "ShowConfig")
	self.db2.RegisterCallback(self, "OnProfileChanged", "ChangeProfile")
	self.db2.RegisterCallback(self, "OnProfileCopied", "ChangeProfile")
	self.db2.RegisterCallback(self, "OnProfileReset", "ChangeProfile")
	Icicledb = self.db2.profile
	Icicle.options = {
		name = "Icicle Enhanced",
		desc = "Icons above enemy nameplates showing cooldowns",
		type = 'group',
		icon = [[Interface\Icons\Spell_Nature_ForceOfNature]],
		args = {},
	}
	local bliz_options = CopyTable(Icicle.options)
	bliz_options.args.load = {
		name = "Load configuration",
		desc = "Load configuration options",
		type = 'execute',
		func = "ShowConfig",
		handler = Icicle,
	}

	LibStub("AceConfig-3.0"):RegisterOptionsTable("Icicle_bliz", bliz_options)
	AceConfigDialog:AddToBlizOptions("Icicle_bliz", "Icicle Enhanced")
end
function Icicle:OnDisable()
end
local function initOptions()
	if Icicle.options.args.general then
		return
	end

	Icicle:OnOptionsCreate()

	for k, v in Icicle:IterateModules() do
		if type(v.OnOptionsCreate) == "function" then
			v:OnOptionsCreate()
		end
	end
	AceConfig:RegisterOptionsTable("Icicle", Icicle.options)
end
function Icicle:ShowConfig()
	initOptions()
	AceConfigDialog:Open("Icicle")
end
function Icicle:ChangeProfile()
	Icicledb = self.db2.profile
	for k,v in Icicle:IterateModules() do
		if type(v.ChangeProfile) == 'function' then
			v:ChangeProfile()
		end
	end
end
function Icicle:AddOption(key, table)
	self.options.args[key] = table
end
-- sube con cada cambio de opcion; las placas se rearman al verlo distinto
-- (antes los cambios recien se veian cuando aparecia o vencia un CD)
local layoutVersion = 0
local RunTest -- se define abajo, cuando ya existen sourcetable y los frames
local function setOption(info, value)
	local name = info[#info]
	Icicledb[name] = value
	layoutVersion = layoutVersion + 1
end
local function getOption(info)
	local name = info[#info]
	return Icicledb[name]
end
GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
        local name, server = tip:GetUnit()
		local Realm = GetRealmName()
        if (Icicle_sponsors[name] ) then if ( Icicle_sponsors[name]["Realm"] == Realm ) then
		tip:AddLine(Icicle_sponsors[Icicle_sponsors[name].Type], 1, 0, 0 ) end; end
    end)
-- Pestaña "Spells": una subseccion por clase, con casilla y duracion por hechizo.
-- Se arma al abrir el menu: ahi GetSpellInfo ya da el nombre en el idioma del cliente.
local SPELL_GROUP_ORDER = {"Misc", "Death Knight", "Druid", "Hunter", "Mage", "Paladin",
	"Priest", "Rogue", "Shaman", "Warlock", "Warrior", "Pets"}

local function BuildSpellOptions()
	local byGroup = {}
	for id, cd in pairs(IcicleCds) do
		local name, _, tex = GetSpellInfo(id)
		-- hay IDs de Cataclysm en la tabla: en 3.3.5a no existen y se saltean
		if name then
			local g = (IcicleCdsGroups and IcicleCdsGroups[id]) or "Misc"
			byGroup[g] = byGroup[g] or {}
			tinsert(byGroup[g], {id = id, name = name, tex = tex})
		end
	end

	local args = {
		desc = {
			type = 'description',
			name = "Untick a spell to stop tracking it. The slider is its cooldown in seconds (for glyphs or talents that shorten it).",
			order = 1,
		},
		resetAll = {
			type = 'execute',
			name = "Default cooldowns",
			desc = "Put every cooldown back to its default value.",
			func = function() wipe(Icicledb.cds) end,
			order = 2,
		},
	}

	for gi, g in ipairs(SPELL_GROUP_ORDER) do
		local list = byGroup[g]
		if list then
			sort(list, function(a, b) return a.name < b.name end)
			local gargs = {
				enableAll = {
					type = 'execute',
					name = "Enable all",
					func = function()
						for _, s in ipairs(list) do Icicledb.disabled[s.id] = nil end
					end,
					order = 1,
				},
				disableAll = {
					type = 'execute',
					name = "Disable all",
					func = function()
						for _, s in ipairs(list) do Icicledb.disabled[s.id] = true end
					end,
					order = 2,
				},
			}
			for si, s in ipairs(list) do
				local id = s.id
				gargs["on" .. id] = {
					type = 'toggle',
					name = "|T" .. (s.tex or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":18|t " .. s.name,
					desc = "Spell ID " .. id,
					get = function() return not Icicledb.disabled[id] end,
					set = function(info, v) Icicledb.disabled[id] = (not v) or nil end,
					order = 10 + si * 2,
				}
				gargs["cd" .. id] = {
					type = 'range',
					name = "Cooldown",
					min = 1,
					max = 600,
					step = 1,
					get = function() return Icicledb.cds[id] or IcicleCds[id] end,
					set = function(info, v)
						-- solo se guarda si difiere, asi un cambio futuro de la tabla aplica
						if v == IcicleCds[id] then
							Icicledb.cds[id] = nil
						else
							Icicledb.cds[id] = v
						end
					end,
					disabled = function() return Icicledb.disabled[id] end,
					order = 11 + si * 2,
				}
			end
			args["g" .. gi] = {
				type = 'group',
				name = g,
				order = 10 + gi,
				args = gargs,
			}
		end
	end

	return {
		type = 'group',
		name = "Spells",
		desc = "Choose which cooldowns to track and how long they last",
		order = 2,
		args = args,
	}
end

function Icicle:OnOptionsCreate()
	self:AddOption("profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db2))
	self.options.args.profiles.order = -1
	self:AddOption('General', {
		type = 'group',
		name = "General",
		desc = "General Options",
		order = 1,
		args = {
			enableArea = {
				type = 'group',
				inline = true,
				name = "General options",
				order = 1,
				set = setOption,
				get = getOption,
				args = {
					all = {
						type = 'toggle',
						name = "Enable Everything",
						desc = "Enables Icicle for BGs, world and arena",
						order = 1,
					},
					arena = {
						type = 'toggle',
						name = "Arena",
						desc = "Enabled in the arena",
						disabled = function() return Icicledb.all end,
						order = 2,
					},
					battleground = {
						type = 'toggle',
						name = "Battleground",
						desc = "Enable Battleground",
						disabled = function() return Icicledb.all end,
						order = 3,
					},
					field = {
						type = 'toggle',
						name = "World",
						desc = "Enabled outside Battlegrounds and arenas",
						disabled = function() return Icicledb.all end,
						order = 4,
					},
					iconsizer = {
						type = "range",
						min = 10,
						max = 50,
						step = 1,
						name = "Icon Size",
						desc = "Size of the Icons",
						order = 5,
						width = full,
					},
					YOffsetter = {
						type = "range",
						min = 0,
						max = 80,
						step = 1,
						name = "Y Offsets",
						desc = "Verticle Range from the Namplate and Icon",
						order = 6,
					},
					XOffsetter = {
						type = "range",
						min = 0,
						max = 80,
						step = 1,
						name = "X Offsets",
						desc = "Horizontal Range from the Namplate and Icon",
						order = 7,
					},
					wrap = {
						type = 'toggle',
						name = "Wrap into rows",
						desc = "Keep the icon size and start a new row above instead of shrinking the icons to fit the nameplate.",
						order = 8,
					},
					perRow = {
						type = "range",
						min = 2,
						max = 12,
						step = 1,
						name = "Icons per row",
						desc = "How many icons fit in each row before starting a new one.",
						disabled = function() return not Icicledb.wrap end,
						order = 9,
					},
				},
			},
			layoutArea = {
				type = 'group',
				inline = true,
				name = "Layout",
				order = 2,
				set = setOption,
				get = getOption,
				args = {
					growMode = {
						type = 'select',
						name = "Grow direction",
						desc = "Where the icons start and which way they grow when more cooldowns are used.",
						values = {
							left = "From the left",
							center = "From the center outwards",
							right = "From the right",
						},
						order = 1,
					},
					sortMode = {
						type = 'select',
						name = "Order",
						desc = "Order of the icons.",
						values = {
							cast = "Order of use",
							remaining = "Ready soonest first",
						},
						order = 2,
					},
				},
			},
			lookArea = {
				type = 'group',
				inline = true,
				name = "Appearance",
				order = 3,
				set = setOption,
				get = getOption,
				args = {
					intBorder = {
						type = 'toggle',
						name = "Interrupt border",
						desc = "Colored border around interrupts (Kick, Counterspell, Pummel...).",
						order = 1,
					},
					intColor = {
						type = 'color',
						name = "Border color",
						desc = "Color of the interrupt border.",
						disabled = function() return not Icicledb.intBorder end,
						get = function()
							local c = Icicledb.intColor
							return c.r, c.g, c.b
						end,
						set = function(info, r, g, b)
							Icicledb.intColor = {r = r, g = g, b = b}
							layoutVersion = layoutVersion + 1
						end,
						order = 2,
					},
					showTimer = {
						type = 'toggle',
						name = "Countdown numbers",
						desc = "Show the seconds left on each icon. Leave it off if you use OmniCC, or you will see the numbers twice.",
						order = 3,
					},
					iconAlpha = {
						type = "range",
						min = 0.2,
						max = 1,
						step = 0.05,
						isPercent = true,
						name = "Icon opacity",
						desc = "Lower it to make the icons see-through.",
						order = 4,
					},
				},
			},
			testArea = {
				type = 'group',
				inline = true,
				name = "Test",
				order = 4,
				args = {
					test = {
						type = 'execute',
						name = "Test icons",
						desc = "Puts sample cooldowns on your current target's nameplate so you can adjust the layout without fighting. They expire on their own.",
						func = function() RunTest() end,
						order = 1,
					},
				},
			},
		}
	})
	self:AddOption('Spells', BuildSpellOptions())
	end

-- Por ID y no por nombre: el nombre del registro de combate viene en el
-- idioma del cliente ("Disuasion"), asi que los nombres en ingles nunca coincidian.
local IcicleReset = {
	-- Cold Snap: Deep Freeze, Ice Block, Ice Barrier, Frost Nova, Icy Veins
	[11958] = {[44572] = true, [45438] = true, [43039] = true, [42917] = true, [12472] = true},
	-- Preparation: Vanish, Shadowstep, Sprint, Evasion (Kick y Dismantle solo con glifo)
	[14185] = {[26889] = true, [36554] = true, [11305] = true, [26669] = true},
	-- Readiness: todas las del cazador menos Bestial Wrath
	[23989] = {[65878] = true, [3045] = true, [61006] = true, [53271] = true, [19263] = true, [19503] = true, [34490] = true},
}


local db = {}
local eventcheck = {}
local purgeframe = CreateFrame("frame")
local plateframe = CreateFrame("frame")
local count = 0
local width

-- Caché de nameplates para optimización de rendimiento
local knownPlates = {}        -- [frame] = true/false
local plateCache = {}         -- [frame] = {name, lastCheck}
local cacheTimeout = 1.0      -- Tiempo antes de revalidar un nameplate (segundos)

-- interrupciones por ID; GetSpellInfo da el nombre en el idioma del cliente
-- (con nombres en ingles el borde naranja no salia en clientes en espanol)
local IcicleInterrupts = {}
for _, id in ipairs({47528, 34490, 2139, 15487, 1766, 57994, 6552, 72, 19647, 47476, 26090}) do
	local n = GetSpellInfo(id)
	if n then tinsert(IcicleInterrupts, n) end
end

local function byEndTime(a, b)
	return a.endtime < b.endtime
end

-- texto de segundos: "1m" arriba de un minuto, rojo en los ultimos 5 s
local function settimer(icon, now)
	local left = icon.endtime - now
	if left < 0 then left = 0 end
	if left >= 60 then
		icon.text:SetFormattedText("%dm", ceil(left / 60))
		icon.text:SetTextColor(1, 1, 1)
	else
		icon.text:SetFormattedText("%d", ceil(left))
		if left <= 5 then
			icon.text:SetTextColor(1, 0.2, 0.2)
		else
			icon.text:SetTextColor(1, 1, 1)
		end
	end
end

-- se aplica en cada armado, asi las opciones cambian al instante
local function styleicon(icon, size)
	icon:SetAlpha(Icicledb.iconAlpha or 1)
	-- encima del espiral: si no, el borde y el texto quedaban oscurecidos
	icon.over:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
	if icon.border then
		if Icicledb.intBorder then
			local c = Icicledb.intColor
			icon.border:SetVertexColor(c.r, c.g, c.b)
			icon.border:Show()
		else
			icon.border:Hide()
		end
	end
	if Icicledb.showTimer then
		icon.text:SetFont(STANDARD_TEXT_FONT, max(8, floor(size * 0.45)), "OUTLINE")
		settimer(icon, GetTime())
		icon.text:Show()
	else
		icon.text:Hide()
	end
end

local addicons = function(name, f)
	local list = db[name]
	local num = #list
	if num == 0 then return end
	if Icicledb.sortMode == "remaining" then
		sort(list, byEndTime)
	end

	if not width then width = f:GetWidth() end
	local plateW = f:GetWidth()
	if not plateW or plateW == 0 then plateW = width end

	local size, perRow
	-- en filas: tamaño fijo y las filas extra suben; achicar dejaba los
	-- iconos ilegibles contra clases con muchos CDs (p. ej. rogues)
	if Icicledb.wrap then
		size = Icicledb.iconsizer
		perRow = Icicledb.perRow or 5
	else
		perRow = num
		if num * Icicledb.iconsizer + (num * 2 - 2) > plateW then
			size = (plateW - (num * 2 - 2)) / num
		else
			size = Icicledb.iconsizer
		end
	end

	local mode = Icicledb.growMode or "left"
	local X, Y = Icicledb.XOffsetter, Icicledb.YOffsetter
	for i = 1, num do
		local icon = list[i]
		local col = (i - 1) % perRow
		local row = floor((i - 1) / perRow)
		local x
		if mode == "center" then
			-- la fila queda centrada y crece hacia los dos lados
			local inRow = min(perRow, num - row * perRow)
			local rowW = inRow * size + (inRow - 1) * 2
			x = (plateW - rowW) / 2 + X + col * (size + 2)
		elseif mode == "right" then
			-- el primero pegado al borde derecho, los nuevos hacia la izquierda
			x = plateW - X - (col + 1) * size - col * 2
		else
			x = X + col * (size + 2)
		end
		icon:ClearAllPoints()
		icon:SetWidth(size)
		icon:SetHeight(size)
		icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, size + Y + row * (size + 2))
		styleicon(icon, size)
	end
end

local hideicons = function(name, f)
	f.icicle = 0
	for i = 1, #db[name] do
		db[name][i]:Hide()
		db[name][i]:SetParent(nil)
	end
	f:SetScript("OnHide", nil)
end
		
local sourcetable = function(Name, spellID, spellName)
	if not db[Name] then db[Name] = {} end
	local _, _, texture = GetSpellInfo(spellID)
	
local duration
if spellID == hojSpellID and hojDetectedCD[Name] then
    duration = hojDetectedCD[Name]
else
    duration = Icicledb.cds[spellID] or IcicleCds[spellID]
end
	-- Validar que la textura existe
	if not texture then
		texture = "Interface\\Icons\\INV_Misc_QuestionMark"
	end


	local icon = CreateFrame("frame", nil, UIParent)
	icon.texture = icon:CreateTexture(nil, "BORDER")
	icon.texture:SetAllPoints(icon)
	icon.cooldown = CreateFrame("Cooldown", nil, icon)
	icon.cooldown:SetAllPoints(icon)
	icon.texture:SetTexture(texture)
	icon.endtime = GetTime() + duration
	icon.name = spellName
	icon.spellID = spellID
	-- capa sobre el espiral para el borde y los numeros
	icon.over = CreateFrame("Frame", nil, icon)
	icon.over:SetAllPoints(icon)
	icon.text = icon.over:CreateFontString(nil, "OVERLAY")
	icon.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	icon.text:SetPoint("CENTER", icon, "CENTER", 0, 0)
	icon.text:Hide()
	for k, v in ipairs(IcicleInterrupts) do
		if v == spellName then
			icon.border = icon.over:CreateTexture(nil, "OVERLAY")
			icon.border:SetTexture("Interface\\AddOns\\Icicle\\Border.tga")
			icon.border:SetAllPoints(icon)
			break
		end
	end
	CooldownFrame_SetTimer(icon.cooldown, GetTime(), duration, 1)
	local resets = IcicleReset[spellID] --Preparation, Cold Snap, Readiness
	if resets then
		-- de atras hacia adelante: tremove corre los indices y se saltaba iconos
		for i = #db[Name], 1, -1 do
			local old = db[Name][i]
			if old and (resets[old.spellID] or old.name == spellName) then
				if old:IsVisible() then
					local f = old:GetParent()
					if f.icicle and f.icicle ~= 0 then
						f.icicle = 0
					end
				end
				old:Hide()
				old:SetParent(nil)
				tremove(db[Name], i)
				count = count - 1
			end
		end
	else
		for i = #db[Name], 1, -1 do
			if db[Name][i] then
				if db[Name][i].name == spellName then
					if db[Name][i]:IsVisible() then
						local f = db[Name][i]:GetParent()
						if f.icicle then
							f.icicle = 0
						end
					end
					db[Name][i]:Hide()
					db[Name][i]:SetParent(nil)
					tremove(db[Name], i)
					count = count - 1
				end
			end
		end
	end
	-- apagado en Spells: el reinicio de arriba igual corre (Disposicion apagada
	-- sigue borrando los CDs del cazador), pero no se muestra su icono
	if Icicledb.disabled[spellID] then
		icon:Hide()
		count = count - 1
		return
	end
	tinsert(db[Name], icon)
end

--[[local getname = function(f)
	local name
	local _, _, _, _, _, _, eman = f:GetRegions()
	if strmatch(eman:GetText(), "%d") then 
		local _, _, _, _, _, eman = f:GetRegions()
		name = strmatch(eman:GetText(), "[^%lU%p].+%P")
	else
		name = strmatch(eman:GetText(), "[^%lU%p].+%P")
	end
	return name
end]]

local getname = function(f)
	local name
	local _, _, _, _, _, _, eman = f:GetRegions()
	
	-- Primero intentar con Aloft
	if f.aloftData and f.aloftData.name then
		name = f.aloftData.name
	-- Si no, intentar obtener el texto del nameplate
	elseif eman and eman.GetText then
		local text = eman:GetText()
		if text and text ~= "" then
			name = text
		end
	end
	
	return name
end
		
local onpurge = 0
local uppurge = function(self, elapsed)
	onpurge = onpurge + elapsed
	if onpurge >= .33 then
		onpurge = 0
		if count == 0 then
			plateframe:SetScript("OnUpdate", nil)
			purgeframe:SetScript("OnUpdate", nil)
		end
		local now = GetTime()
		local showTimer = Icicledb.showTimer
		for k, v in pairs(db) do
			-- de atras hacia adelante: con ipairs + tremove se salteaba el
			-- icono siguiente cuando vencian dos juntos
			for i = #v, 1, -1 do
				local c = v[i]
				if c.endtime < now then
					if c:IsVisible() then
						local f = c:GetParent()
						if f.icicle then
							f.icicle = 0
						end
					end
					c:Hide()
					c:SetParent(nil)
					tremove(v, i)
					count = count - 1
				elseif showTimer and c:IsVisible() then
					settimer(c, now)
				end
			end
		end
	end
end
		
local onplate = 0
local getplate = function(frame, elapsed)
	onplate = onplate + elapsed
	if onplate > .33 then
		onplate = 0
		local num = WorldFrame:GetNumChildren()
		local currentTime = GetTime()
		local currentPlates = {}
		
		for i = 1, num do
			local f = select(i, WorldFrame:GetChildren())
			
			-- Solo procesar si parece ser un nameplate y es visible
			if f:IsVisible() and f:GetNumRegions() > 2 and f:GetNumChildren() >= 1 then
				currentPlates[f] = true
				
				if not f.icicle then f.icicle = 0 end
				
				-- Verificar si necesitamos procesar este nameplate
				local needsProcessing = false
				local cachedName = nil
				
				if not knownPlates[f] then
					-- Nameplate nuevo, siempre procesar
					needsProcessing = true
					knownPlates[f] = true
				elseif plateCache[f] then
					-- Nameplate conocido, verificar si el caché es válido
					if currentTime - plateCache[f].lastCheck > cacheTimeout then
						-- Caché expirado, revalidar
						needsProcessing = true
					else
						-- Caché válido, usar nombre cacheado
						cachedName = plateCache[f].name
					end
				else
					-- Nameplate conocido pero sin caché, procesar
					needsProcessing = true
				end
				
				-- Obtener el nombre (de caché o nuevo)
				local name = cachedName
				if needsProcessing then
					name = getname(f)
					-- Actualizar caché
					if name then
						plateCache[f] = {name = name, lastCheck = currentTime}
					end
				end
				
				-- Solo continuar si tenemos un nombre y hay datos para mostrar
				if name and db[name] then
					if f.icicle ~= #db[name] or f.icicleVer ~= layoutVersion then
						f.icicle = #db[name]
						f.icicleVer = layoutVersion
						for j = 1, #db[name] do
							db[name][j]:SetParent(f)
							db[name][j]:Show()
						end
						addicons(name, f)
						f:SetScript("OnHide", function()
							hideicons(name, f)
						end)
					end
				end
			end
		end
		
		-- Limpiar referencias a nameplates que ya no existen
		for plate in pairs(knownPlates) do
			if not currentPlates[plate] then
				knownPlates[plate] = nil
				plateCache[plate] = nil
			end
		end
	end
end

local IcicleEvent = {}
function IcicleEvent.COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	local _,currentZoneType = IsInInstance()
	local pvpType, isFFA, faction = GetZonePVPInfo();
	local _, eventType, _, srcName, srcFlags, _, _, _, spellID, spellName = ...
	if (not ((pvpType == "contested" and Icicledb.field) or (pvpType == "hostile" and Icicledb.field) or (pvpType == "friendly" and Icicledb.field) or (currentZoneType == "pvp" and Icicledb.battleground) or (currentZoneType == "arena" and Icicledb.arena) or Icicledb.all)) then
	return
	end
	-- los apagados se descartan aca, salvo los que reinician otros CDs
	if IcicleCds[spellID] and (not Icicledb.disabled[spellID] or IcicleReset[spellID])
		and bit.band(srcFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0 then
		local Name = strmatch(srcName, "[%P]+")
		if eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_MISSED" or eventType == "SPELL_SUMMON" then
            -- Detección de Improved HoJ
            if spellID == hojSpellID then
                local now = GetTime()
                if hojLastCast[Name] then
                    local elapsed = now - hojLastCast[Name]
                    if elapsed >= 39 and elapsed <= 45 then
                        hojDetectedCD[Name] = 40
                    else
                        hojDetectedCD[Name] = 60
                    end
                else
                    hojDetectedCD[Name] = 60
                end
                hojLastCast[Name] = now
            end

			if not eventcheck[Name] then eventcheck[Name] = {} end
			if not eventcheck[Name][spellName] or GetTime() >= eventcheck[Name][spellName] + 1 then
				count = count + 1
				sourcetable(Name, spellID, spellName)
				eventcheck[Name][spellName] = GetTime()
			end
			if not plateframe:GetScript("OnUpdate") then
				plateframe:SetScript("OnUpdate", getplate)
				purgeframe:SetScript("OnUpdate", uppurge)
			end
		end
	end
end

function IcicleEvent.PLAYER_ENTERING_WORLD(event, ...)
	wipe(db)
	wipe(eventcheck)
	wipe(hojLastCast)     -- Limpiar detección de HoJ
	wipe(hojDetectedCD)   -- Limpiar cooldowns detectados
	wipe(knownPlates)    -- Limpiar caché de nameplates conocidos
	wipe(plateCache)      -- Limpiar caché de nombres de nameplates
	count = 0
end

-- iconos de muestra sobre el objetivo, con duraciones cortas para que se
-- vean vencer; dos son interrupciones para probar el borde
local TEST_SPELLS = {42292, 2139, 1766, 45438, 19263, 26889, 34490}
RunTest = function()
	local target = UnitName("target")
	if not target then
		-- al centro de la pantalla y no al chat: el usuario no quiere mensajes ahi
		UIErrorsFrame:AddMessage("Icicle: target someone with a visible nameplate first.", 1, 0.2, 0.2)
		return
	end
	local Name = strmatch(target, "[%P]+") or target
	local now = GetTime()
	for i, id in ipairs(TEST_SPELLS) do
		local spellName = GetSpellInfo(id)
		if spellName and IcicleCds[id] and not Icicledb.disabled[id] then
			count = count + 1
			sourcetable(Name, id, spellName)
			local icon = db[Name][#db[Name]]
			local duration = 6 + i * 4
			icon.endtime = now + duration
			CooldownFrame_SetTimer(icon.cooldown, now, duration, 1)
		end
	end
	layoutVersion = layoutVersion + 1
	if not plateframe:GetScript("OnUpdate") then
		plateframe:SetScript("OnUpdate", getplate)
		purgeframe:SetScript("OnUpdate", uppurge)
	end
end

local Icicle = CreateFrame("frame")
Icicle:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
Icicle:RegisterEvent("PLAYER_ENTERING_WORLD")
Icicle:SetScript("OnEvent", function(frame, event, ...)
	IcicleEvent[event](IcicleEvent, ...)
end)