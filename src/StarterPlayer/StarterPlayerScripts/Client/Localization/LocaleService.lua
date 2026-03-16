-- LocaleService.lua
-- Roblox locale 기반 언어 결정 (ko/en)

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocaleService = {}

local initialized = false
local currentLanguage = "ko"

local function resolveLanguageFromLocale(localeId: string?): string
	local locale = string.lower(tostring(localeId or ""))
	if locale == "" then
		return "ko"
	end

	if string.sub(locale, 1, 2) == "ko" then
		return "ko"
	end

	return "en"
end

function LocaleService.Init()
	if initialized then return end

	if RunService:IsStudio() then
		local studioLang = nil
		local player = Players.LocalPlayer
		if player then
			local attr = player:GetAttribute("StudioLanguageOverride")
			if type(attr) == "string" then
				local normalized = string.lower(attr)
				if normalized == "ko" or normalized == "en" then
					studioLang = normalized
				end
			end
		end

		currentLanguage = studioLang or "ko"
		initialized = true
		print(string.format("[LocaleService] Initialized: %s (studio default, override=%s)", currentLanguage, tostring(studioLang)))
		return
	end

	local localeId = nil
	local source = "unknown"

	-- 1) Roblox 계정 Locale 우선 (UI 표시 언어와 가장 일치)
	pcall(function()
		localeId = LocalizationService.RobloxLocaleId
		source = "roblox"
	end)

	-- 2) 플레이어 번역기 Locale (경험 언어) fallback
	pcall(function()
		if not localeId or localeId == "" then
			local player = Players.LocalPlayer
			if player then
				local translator = LocalizationService:GetTranslatorForPlayerAsync(player)
				if translator and translator.LocaleId and translator.LocaleId ~= "" then
					localeId = translator.LocaleId
					source = "translator"
				end
			end
		end
	end)

	-- 3) 시스템 Locale
	pcall(function()
		if (not localeId or localeId == "") and LocalizationService.SystemLocaleId then
			localeId = LocalizationService.SystemLocaleId
			source = "system"
		end
	end)

	currentLanguage = resolveLanguageFromLocale(localeId)
	initialized = true
	print(string.format("[LocaleService] Initialized: %s (locale=%s, source=%s)", currentLanguage, tostring(localeId), source))
end

function LocaleService.GetLanguage(): string
	if not initialized then
		LocaleService.Init()
	end
	return currentLanguage
end

function LocaleService.IsKorean(): boolean
	return LocaleService.GetLanguage() == "ko"
end

return LocaleService
