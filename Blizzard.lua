local _, Merlin = ...

local suppressed = false

local function KeepHidden(frame)
	if not frame or InCombatLockdown() then
		return
	end
	if frame:IsShown() then
		frame:Hide()
	end
end

-- Suppress stock BuffFrame and ExternalDefensivesFrame completely, and hide
-- DebuffFrame's visual AuraContainer while keeping DebuffFrame itself active
-- and parented so Blizzard's DeadlyDebuffFrame continues receiving updates.
function Merlin.SuppressBlizzardAuras()
	if suppressed then
		return
	end
	suppressed = true

	if BuffFrame then
		BuffFrame:UnregisterAllEvents()
		BuffFrame:SetAlpha(0)
		BuffFrame:EnableMouse(false)
		BuffFrame:Hide()
		hooksecurefunc(BuffFrame, "Show", KeepHidden)
	end

	if DebuffFrame then
		DebuffFrame:SetAlpha(0)
		DebuffFrame:EnableMouse(false)
		local container = DebuffFrame.AuraContainer
		if container then
			-- Keep DebuffFrame as AuraContainer's parent so UpdateGridLayout's
			-- self:GetParent():UpdateSize(...) never hits a foreign parent.
			container:SetAlpha(0)
			if container.EnableMouse then
				container:EnableMouse(false)
			end
			container:Hide()
			hooksecurefunc(container, "Show", KeepHidden)
		end
	end

	if ExternalDefensivesFrame then
		ExternalDefensivesFrame:UnregisterAllEvents()
		ExternalDefensivesFrame:SetAlpha(0)
		ExternalDefensivesFrame:EnableMouse(false)
		ExternalDefensivesFrame:Hide()
		hooksecurefunc(ExternalDefensivesFrame, "Show", KeepHidden)
	end
end

function Merlin.ReapplyBlizzardSuppression()
	if not suppressed or InCombatLockdown() then
		return
	end
	KeepHidden(BuffFrame)
	if DebuffFrame and DebuffFrame.AuraContainer then
		KeepHidden(DebuffFrame.AuraContainer)
	end
	KeepHidden(ExternalDefensivesFrame)
end
