require "import"
import "android.widget.*"
import "android.content.Intent"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"
import "android.view.View"
import "android.content.Context"
import "android.text.TextWatcher"
import "android.net.Uri"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.nio.channels.FileChannel"
import "android.os.SystemClock"
import "android.view.GestureDetector"
import "android.view.MotionEvent"
import "android.os.Environment"
import "com.androlua.Http"
import "cjson"

-- ============================================================
-- فائل راستے
-- ============================================================
local backupFolder = os.getenv("EXTERNAL_STORAGE") .. "/解说/Plugins/digital typer/backup"
local dictFile = backupFolder .. "/dictionary.txt"
local settingsFile = backupFolder .. "/digital_typer_settings.txt"
local dictBackupFile = backupFolder .. "/dictionary_backup.txt"
local settingsBackupFile = backupFolder .. "/digital_typer_settings_backup.txt"

-- ڈکشنری ٹیبل
local changeTable = {}

-- سیٹنگز
local settings = { punctuation = "newline", showLangDialog = true, autoCorrectUrdu = false }
local favouriteIndices = {}
local primaryLangCode = "en-PK"
local secondaryLangCode = "ur-PK"

-- ==================== GOOGLE GEMINI CONFIG ====================
local GEMINI_PREFS = "UniqueTyperAI"
local geminiPrefs = service.getSharedPreferences(GEMINI_PREFS, Context.MODE_PRIVATE)
local geminiEditor = geminiPrefs.edit()

local GEMINI_MODELS = {
    "Gemini 2.5 Flash",
    "Gemini 2.5 Pro",
    "Gemini 2.0 Flash"
}

local geminiApiDetails = {
    ["Gemini 2.5 Flash"] = { id = "models/gemini-2.5-flash", version = "v1beta" },
    ["Gemini 2.5 Pro"] = { id = "models/gemini-2.5-pro", version = "v1beta" },
    ["Gemini 2.0 Flash"] = { id = "models/gemini-2.0-flash", version = "v1beta" }
}

function getGeminiApiKey()
    return geminiPrefs.getString("gemini_apiKey", "")
end

function saveGeminiApiKey(key)
    geminiEditor.putString("gemini_apiKey", key)
    geminiEditor.commit()
end

function getGeminiModel()
    return geminiPrefs.getString("gemini_model", "Gemini 2.5 Flash")
end

function saveGeminiModel(model)
    geminiEditor.putString("gemini_model", model)
    geminiEditor.commit()
end

-- ==================== GROQ AI CONFIG ====================
local GROQ_PREFS = "GroqAITyper"
local groqPrefs = service.getSharedPreferences(GROQ_PREFS, Context.MODE_PRIVATE)
local groqEditor = groqPrefs.edit()

local GROQ_MODELS = {
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "mixtral-8x7b-32768",
    "gemma2-9b-it",
    "llama-guard-3-8b"
}

function getGroqApiKey()
    return groqPrefs.getString("groq_apiKey", "")
end

function saveGroqApiKey(key)
    groqEditor.putString("groq_apiKey", key)
    groqEditor.commit()
end

-- ==================== GROQ MODEL SETTINGS ====================
function getGroqModel()
    return groqPrefs.getString("groq_model", "llama-3.3-70b-versatile")
end

function saveGroqModel(model)
    groqEditor.putString("groq_model", model)
    groqEditor.commit()
end

-- ==================== SHARED AI SETTINGS ====================
local SHARED_PREFS = "AI_Shared"
local sharedPrefs = service.getSharedPreferences(SHARED_PREFS, Context.MODE_PRIVATE)
local sharedEditor = sharedPrefs.edit()

function getSelectedAIEngine()
    return sharedPrefs.getString("ai_engine", "gemini")
end

function saveSelectedAIEngine(engine)
    sharedEditor.putString("ai_engine", engine)
    sharedEditor.commit()
end

function isEmojiEnabled()
    return sharedPrefs.getBoolean("emojiEnabled", false)
end

function setEmojiEnabled(enabled)
    sharedEditor.putBoolean("emojiEnabled", enabled)
    sharedEditor.commit()
end

function isApiTypingEnabled()
    return sharedPrefs.getBoolean("apiTypingEnabled", true)
end

function setApiTypingEnabled(enabled)
    sharedEditor.putBoolean("apiTypingEnabled", enabled)
    sharedEditor.commit()
end

-- ==================== STRICT AI INSTRUCTION ====================
local DEFAULT_INSTRUCTION = [[You are a professional text grammar and spelling correction tool. Correct the given raw spoken text strictly according to these rules:
1. STRICT RULE: Every single English word MUST be written strictly in the English alphabet/script. Do not transliterate English words into Urdu.
2. Keep Urdu words strictly in Urdu script. Fix any spelling issues in Urdu.
3. CRITICAL ALIF vs ALIF MADDA RULE: 
   - ONLY use Alif Madda (آ) for words that genuinely start with the long 'aa' sound (e.g., "آپ", "آج", "آدمی", "آسمان", "آواز", "آسان").
   - MUST use standard Alif (ا) for words that start with a short 'a' or other vowel sounds (e.g., "اب", "اس", "اندر", "اپنا", "استعمال", "اچھا"). 
   - DO NOT unnecessarily add Alif Madda to words that require standard Alif.
4. Ensure proper spacing between words. Do not add any introductory text, pleasantries, emojis (unless requested), or "Corrected text:". Return ONLY the corrected sentence.]]

local DICTIONARY_CORRECTION_INSTRUCTION = [[You are a strict Urdu spelling correction engine. You are given a list of raw words written in Urdu script.
Your absolute assignment is to correct the Urdu spellings of these words inside the Urdu script itself.
CRITICAL LAWS:
1. Output corrected words strictly in URDU SCRIPT ONLY.
2. CRITICAL ALIF LAW: Properly differentiate between Alif Madda (آ) and Alif (ا). Do not blindly apply Alif Madda to words that need standard Alif (e.g., "اب", "اپنا", "اچھا").
3. Never convert or translate to English characters.
4. Just output space-separated corrected Urdu words.]]

-- ==================== API CALLS ====================
function testGeminiAPI(apiKey, model, callback)
    local url = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. apiKey
    Http.get(url, {}, function(status, data)
        if status == 200 then callback(true, "API key is valid!")
        else callback(false, "Invalid API key or error: " .. status) end
    end)
end

function callGeminiAPI(apiKey, model, prompt, systemInstruction, callback)
    local modelInfo = geminiApiDetails[model]
    if not modelInfo then callback(nil, "Error: Model not found") return end
    
    local cleanKey = apiKey:gsub("%s+", "")
    local url = "https://generativelanguage.googleapis.com/" .. modelInfo.version .. "/" .. modelInfo.id .. ":generateContent?key=" .. cleanKey
    
    local payload = {
        contents = { { parts = { { text = prompt } } } },
        systemInstruction = { parts = { { text = systemInstruction or DEFAULT_INSTRUCTION } } }
    }
    
    local headers = { ["Content-Type"] = "application/json" }
    Http.post(url, cjson.encode(payload), headers, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.candidates and decoded.candidates[1] then
                local text = decoded.candidates[1].content and decoded.candidates[1].content.parts and decoded.candidates[1].content.parts[1] and decoded.candidates[1].content.parts[1].text
                if text then callback(text, nil) else callback(nil, "Invalid response from Gemini") end
            else callback(nil, "Failed to parse Gemini response") end
        else 
            callback(nil, "Gemini Error: " .. status) 
        end
    end)
end

function testGroqAPI(apiKey, model, callback)
    local url = "https://api.groq.com/openai/v1/models"
    local headers = { ["Authorization"] = "Bearer " .. apiKey }
    Http.get(url, headers, function(status, data)
        if status == 200 then callback(true, "API key is valid!")
        elseif status == 401 then callback(false, "Invalid API key")
        else callback(false, "Error: " .. status) end
    end)
end

function callGroqAPI(apiKey, model, systemPrompt, userPrompt, callback)
    local url = "https://api.groq.com/openai/v1/chat/completions"
    local headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. apiKey }
    local messages = {}
    table.insert(messages, {role = "system", content = systemPrompt or DEFAULT_INSTRUCTION})
    table.insert(messages, {role = "user", content = userPrompt})
    local payload = { model = model, messages = messages, max_tokens = 1024, temperature = 0.2 }
    Http.post(url, cjson.encode(payload), headers, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.choices and decoded.choices[1] then
                local text = decoded.choices[1].message.content
                if text then callback(text, nil) else callback(nil, "Invalid response from Groq") end
            else callback(nil, "Failed to parse Groq response") end
        elseif status == 401 then callback(nil, "Invalid API key")
        elseif status == 429 then callback(nil, "Rate limit exceeded")
        else callback(nil, "Groq Error: " .. status) end
    end)
end

function getGeminiPrompt(spokenText)
    local extra = isEmojiEnabled() and " Add ONE relevant emoji." or " Do NOT add any emojis."
    return "Fix this spoken text keeping script languages intact. Pay precise attention to Alif (ا) and Alif Madda (آ) rules:" .. extra .. "\n\nInput Text: " .. spokenText
end

function cleanAIResponse(text)
    if not text then return "" end
    text = text:gsub("^[%s]*Corrected:?%s*", "")
    text = text:gsub("^[%s]*Output:?%s*", "")
    text = text:gsub("^[%s]*Here is the corrected text:?%s*", "")
    text = text:gsub("%s*$", "")
    return text
end

function showErrorPopup(message)
    local dlg = LuaDialog(service)
    dlg.setTitle("API Error")
    dlg.setMessage(message)
    dlg.setButton("Cancel", function() dlg.dismiss() end)
    dlg.show()
end

function processWithAI(spokenText, callback)
    local engine = getSelectedAIEngine()
    if engine == "groq" then
        local apiKey = getGroqApiKey()
        if not apiKey or apiKey == "" then
            service.speak("Please set Groq API key in AI settings first")
            callback(spokenText)
            return
        end
        local model = getGroqModel()
        callGroqAPI(apiKey, model, DEFAULT_INSTRUCTION, spokenText, function(result, error)
            if error then showErrorPopup(error)
            else callback(cleanAIResponse(result)) end
        end)
    else
        local apiKey = getGeminiApiKey()
        if not apiKey or apiKey == "" then
            callback(spokenText)
            return
        end
        local model = getGeminiModel()
        local prompt = getGeminiPrompt(spokenText)
        callGeminiAPI(apiKey, model, prompt, DEFAULT_INSTRUCTION, function(result, error)
            if error then showErrorPopup(error)
            else callback(cleanAIResponse(result)) end
        end)
    end
end

-- ==================== AI SETTINGS DIALOG ====================
function showAISettingsDialog(mainDlg)
    local dlg = LuaDialog(service)
    dlg.setTitle("AI Engine Settings")
    dlg.setCancelable(true)
    
    local mainLayout = LinearLayout(service)
    mainLayout.setOrientation(1)
    mainLayout.setPadding(30, 20, 30, 20)
    
    local engineLabel = TextView(service)
    engineLabel.setText("Select AI Engine:")
    engineLabel.setTextSize(14)
    engineLabel.setTextColor(0xFFFFFFFF)
    engineLabel.setPadding(0, 0, 0, 10)
    mainLayout.addView(engineLabel)
    
    local engineSpinner = Spinner(service)
    local engines = {"Gemini", "Groq"}
    local engineAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, engines)
    engineAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    engineSpinner.setAdapter(engineAdapter)
    local currentEngine = getSelectedAIEngine()
    engineSpinner.setSelection(currentEngine == "groq" and 1 or 0)
    mainLayout.addView(engineSpinner)
    
    local settingsContainer = LinearLayout(service)
    settingsContainer.setOrientation(1)
    settingsContainer.setPadding(0, 20, 0, 0)
    mainLayout.addView(settingsContainer)
    
    local apiBtn = Button(service)
    local apiState = isApiTypingEnabled()
    apiBtn.setText(apiState and "Typing with API: ON" or "Typing with API: OFF")
    apiBtn.setTextSize(14)
    apiBtn.setBackgroundColor(0xFF333333)
    apiBtn.setPadding(0, 15, 0, 15)
    local apiBtnParams = LinearLayout.LayoutParams(-1, -2)
    apiBtnParams.bottomMargin = 20
    apiBtn.setLayoutParams(apiBtnParams)
    apiBtn.setOnClickListener(function()
        local newState = not isApiTypingEnabled()
        setApiTypingEnabled(newState)
        saveAllSettings()
        apiBtn.setText(newState and "Typing with API: ON" or "Typing with API: OFF")
        service.speak("API Typing " .. (newState and "enabled" or "disabled"))
    end)
    mainLayout.addView(apiBtn)
    
    local buttonRow = LinearLayout(service)
    buttonRow.setOrientation(0)
    buttonRow.setPadding(0, 20, 0, 0)
    
    local saveBtn = Button(service)
    saveBtn.setText("SAVE")
    saveBtn.setTextSize(12)
    saveBtn.setBackgroundColor(0xFF4CAF50)
    saveBtn.setPadding(0, 15, 0, 15)
    saveBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    saveBtn.getLayoutParams().setMargins(5, 0, 5, 0)
    
    local backBtn = Button(service)
    backBtn.setText("GO BACK")
    backBtn.setTextSize(12)
    backBtn.setBackgroundColor(0xFFF44336)
    backBtn.setPadding(0, 15, 0, 15)
    backBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    backBtn.getLayoutParams().setMargins(5, 0, 0, 0)
    
    buttonRow.addView(saveBtn)
    buttonRow.addView(backBtn)
    mainLayout.addView(buttonRow)
    
    local function updateSettingsUI(engine)
        settingsContainer.removeAllViews()
        if engine == "groq" then
            local groqKeyLabel = TextView(service)
            groqKeyLabel.setText("Groq API Key:")
            groqKeyLabel.setTextSize(14)
            settingsContainer.addView(groqKeyLabel)
            
            local groqKeyInput = EditText(service)
            groqKeyInput.setHint("Enter Groq API Key")
            local savedGroqKey = getGroqApiKey()
            if savedGroqKey ~= "" then groqKeyInput.setText(savedGroqKey) end
            groqKeyInput.setBackgroundColor(0xFF222222)
            settingsContainer.addView(groqKeyInput)
            
            local groqModelSpinner = Spinner(service)
            local groqAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GROQ_MODELS)
            groqAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            groqModelSpinner.setAdapter(groqAdapter)
            local currentGroqModel = getGroqModel()
            for i, m in ipairs(GROQ_MODELS) do
                if m == currentGroqModel then groqModelSpinner.setSelection(i-1) break end
            end
            settingsContainer.addView(groqModelSpinner)
            
            saveBtn.setOnClickListener(function()
                local key = groqKeyInput.getText().toString()
                local model = GROQ_MODELS[groqModelSpinner.getSelectedItemPosition() + 1]
                if key ~= "" then saveGroqApiKey(key) end
                if model then saveGroqModel(model) end
                saveSelectedAIEngine("groq")
                saveAllSettings()
                service.speak("Settings saved")
                dlg.dismiss()
                if mainDlg then mainDlg.show() end
            end)
        else
            local geminiKeyLabel = TextView(service)
            geminiKeyLabel.setText("Gemini API Key:")
            settingsContainer.addView(geminiKeyLabel)
            
            local geminiKeyInput = EditText(service)
            geminiKeyInput.setHint("Enter Gemini API Key")
            local savedGeminiKey = getGeminiApiKey()
            if savedGeminiKey ~= "" then geminiKeyInput.setText(savedGeminiKey) end
            geminiKeyInput.setBackgroundColor(0xFF222222)
            settingsContainer.addView(geminiKeyInput)
            
            local geminiModelSpinner = Spinner(service)
            local geminiAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GEMINI_MODELS)
            geminiAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            geminiModelSpinner.setAdapter(geminiAdapter)
            local currentGeminiModel = getGeminiModel()
            for i, m in ipairs(GEMINI_MODELS) do
                if m == currentGeminiModel then geminiModelSpinner.setSelection(i-1) break end
            end
            settingsContainer.addView(geminiModelSpinner)
            
            saveBtn.setOnClickListener(function()
                local key = geminiKeyInput.getText().toString()
                local model = GEMINI_MODELS[geminiModelSpinner.getSelectedItemPosition() + 1]
                if key ~= "" then saveGeminiApiKey(key) end
                if model then saveGeminiModel(model) end
                saveSelectedAIEngine("gemini")
                saveAllSettings()
                service.speak("Settings saved")
                dlg.dismiss()
                if mainDlg then mainDlg.show() end
            end)
        end
    end
    
    engineSpinner.setOnItemSelectedListener({
        onItemSelected = function(parent, view, position, id)
            updateSettingsUI(engines[position+1]:lower())
        end,
        onNothingSelected = function() end
    })
    
    updateSettingsUI(currentEngine)
    
    backBtn.setOnClickListener(function()
        dlg.dismiss()
        if mainDlg then mainDlg.show() end
    end)
    
    local scrollView = ScrollView(service)
    scrollView.addView(mainLayout)
    dlg.setView(scrollView)
    dlg.show()
end

-- ==================== AUTO CORRECT SETTINGS MENU ====================
function showAutoCorrectMenu(returnDlg)
    local dlg = LuaDialog(service)
    dlg.setTitle("Auto Correct Settings")
    local layout = LinearLayout(service)
    layout.setOrientation(1)
    layout.setPadding(30, 20, 30, 20)
    
    local toggleBtn = Button(service)
    local function updateToggleText()
        toggleBtn.setText(settings.autoCorrectUrdu and "Auto Correct: ON" or "Auto Correct: OFF")
        toggleBtn.setBackgroundColor(settings.autoCorrectUrdu and 0xFF4CAF50 or 0xFFF44336)
    end
    updateToggleText()
    
    toggleBtn.setOnClickListener(function()
        settings.autoCorrectUrdu = not settings.autoCorrectUrdu
        saveAllSettings()
        updateToggleText()
        service.speak(settings.autoCorrectUrdu and "Auto Correct Enabled" or "Auto Correct Disabled")
    end)
    layout.addView(toggleBtn)
    
    local closeBtn = Button(service)
    closeBtn.setText("Save and Close")
    closeBtn.setOnClickListener(function() 
        dlg.dismiss() 
        if returnDlg then returnDlg.show() end
    end)
    layout.addView(closeBtn)
    
    dlg.setView(layout)
    dlg.show()
end

-- ============================================================
-- زبانیں اور فائل ہینڈلنگ
-- ============================================================
local allLanguages = {
  {name = "English (Pakistan)", code = "en-PK"},
  {name = "Hindi (India)", code = "hi-IN"},
  {name = "Urdu (Pakistan)", code = "ur-PK"},
  {name = "Arabic (Saudi Arabia)", code = "ar-SA"},
}

local languageItems, languageCodes = {}, {}
for i, lang in ipairs(allLanguages) do
  languageItems[i] = lang.name
  languageCodes[i] = lang.code
end

function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

function saveDictionary()
  ensureBackupFolder()
  local items = {}
  for k, v in pairs(changeTable) do
      table.insert(items, string.format("[%q]=%q", k, v))
  end
  local content = "return {\n" .. table.concat(items, ",\n") .. "\n}"
  local f = io.open(dictFile, "w")
  if f then f:write(content) f:close() return true end
  return false
end

-- ============================================================
-- DICTIONARY CORE FUNCTIONS (UNLIMITED CAPACITY)
-- ============================================================
local DICT_CLEARED_KEY = "dict_cleared"

function isDictionaryCleared()
    return sharedPrefs.getBoolean(DICT_CLEARED_KEY, false)
end

function setDictionaryCleared(cleared)
    sharedEditor.putBoolean(DICT_CLEARED_KEY, cleared)
    sharedEditor.commit()
end

-- یہاں الف مدہ کے اہم ترین الفاظ کی فہرست دی گئی ہے۔ 
-- باقی ہزاروں الفاظ آپ dictionary.txt کے اندر جتنے چاہیں بڑھا سکتے ہیں، ایپ کریش نہیں کرے گی۔
function addAlifMaddaWords()
  if isDictionaryCleared() then return end
  local alifMaddaMap = {
    ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
    ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
    ["انسو"] = "آنسو", ["اخری"] = "آخری", ["واز"] = "آواز", ["انکھیں"] = "آنکھیں",
    ["اداب"] = "آداب", ["اسان"] = "آسان", ["آم"] = "آم", ["ایت"] = "آیت",
    ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
    ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے",
    ["ازاد"] = "آزاد", ["ازادی"] = "آزادی", ["اسپاس"] = "آس پاس",
    ["ایندہ"] = "آئندہ", ["اغاز"] = "آغاز", ["ابادی"] = "آبادی", 
    ["الو"] = "آلو", ["امدن"] = "آمدن", ["امدی"] = "آمدی", 
    ["اڑو"] = "آڑو", ["اری"] = "آری", ["اہستہ"] = "آہستہ", 
    ["اخر"] = "آخر", ["ادھا"] = "آدھا", ["ادھے"] = "آدھے", ["ادھی"] = "آدھی",
    ["اشنا"] = "آشنا", ["اغوش"] = "آغوش", ["الہ"] = "آلہ", 
    ["اموز"] = "آموز", ["انچ"] = "آنچ", ["اندھی"] = "آندھی", 
    ["انگن"] = "آنگن", ["اہٹ"] = "آہٹ", ["ائینہ"] = "آئینہ"
  }
  for wrong, correct in pairs(alifMaddaMap) do
    if not changeTable[wrong] then changeTable[wrong] = correct end
  end
  saveDictionary()
end

function loadDictionary()
  local f = io.open(dictFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      content = content:gsub("^\239\187\191", "")
      local func = loadstring(content)
      if func then
        local dict = func()
        if type(dict) == "table" then
          changeTable = dict
          addAlifMaddaWords()
          return
        end
      end
    end
  end
  changeTable = {}
  addAlifMaddaWords()
end

function clearAllDictionary()
  changeTable = {}
  setDictionaryCleared(true)  
  saveDictionary()
end

function addToDictionary(wrongWord, correctWord)
  if wrongWord and correctWord and wrongWord ~= "" and correctWord ~= "" then
    changeTable[wrongWord] = correctWord
    saveDictionary()
    return true
  end
  return false
end

function deleteFromDictionary(wrongWord)
  if changeTable[wrongWord] then
    changeTable[wrongWord] = nil
    saveDictionary()
    return true
  end
  return false
end

-- ============================================================
-- SMART WORD BOUNDARY REPLACEMENT (The Fix for 'اپنا' -> 'آپنا' Bug)
-- ============================================================
function applyDictionaryReplacements(text)
  if not text or text == "" then return text end
  local result = ""
  local lastPos = 1
  -- یہ لاجک جملے کو الفاظ میں توڑتی ہے اور صرف مکمل لفظ میچ ہونے پر تبدیل کرتی ہے۔
  -- اس وجہ سے "اپ" کبھی بھی "اپنا" کے اندر مکس نہیں ہوگا اور ہزاروں الفاظ پر بھی سپیڈ پرفیکٹ رہے گی۔
  for word in text:gmatch("[^%s%p۔،؟]+") do
      local startPos, endPos = text:find(word, lastPos, true)
      if startPos then
          result = result .. text:sub(lastPos, startPos - 1)
          if changeTable[word] then
              result = result .. changeTable[word]
          else
              result = result .. word
          end
          lastPos = endPos + 1
      end
  end
  result = result .. text:sub(lastPos)
  return result
end

function showDictionaryManager()
  local dlg = LuaDialog(service)
  dlg.setTitle("Digital Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { Button; text = "Add Word"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showAddWordDialog() end; };
    { Button; text = "View / Delete Words"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showViewWordsDialog() end; };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showAddWordDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Add Word Replacement")
  local views = {}
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "20dp";
    { TextView; text = "Wrong Word Spoken:"; };
    { EditText; id = "wrongInput"; layout_width = "fill"; layout_marginBottom = "15dp"; };
    { TextView; text = "Correct Word to Replace With:"; };
    { EditText; id = "correctInput"; layout_width = "fill"; layout_marginBottom = "20dp"; };
    { LinearLayout; orientation = "horizontal"; layout_width = "fill";
      { Button; text = "Save"; layout_width = "0dp"; layout_weight = 1; onClick = function()
          local w = string.match(views.wrongInput.getText().toString(), "^%s*(.-)%s*$")
          local c = string.match(views.correctInput.getText().toString(), "^%s*(.-)%s*$")
          if w ~= "" and c ~= "" then
            addToDictionary(w, c)
            service.speak("Saved successfully")
            dlg.dismiss()
          end
        end;
      };
      { Button; text = "Cancel"; layout_width = "0dp"; layout_weight = 1; onClick = function() dlg.dismiss() end; };
    };
  }
  dlg.setView(loadlayout(layout, views))
  dlg.show()
end

function showViewWordsDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Dictionary Words")
  local list = ListView(service)
  local wordsList = ArrayList() 
  local rawKeys = {}
  for k, v in pairs(changeTable) do
    table.insert(rawKeys, k)
    wordsList.add(tostring(k) .. " -> " .. tostring(v)) 
  end
  local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, wordsList)
  list.setAdapter(adapter)
  
  dlg.setButton("Empty", function()
      clearAllDictionary()
      service.speak("Dictionary cleared completely")
      dlg.dismiss()
  end)
  dlg.setButton2("Close", function() dlg.dismiss() end)
  dlg.setView(list)
  dlg.show()
end

function loadAllSettings()
  local f = io.open(settingsFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      local func = loadstring(content)
      if func then
        local data = func()
        if type(data) == "table" then
          primaryLangCode = data.primary or "en-PK"
          secondaryLangCode = data.secondary or "ur-PK"
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.autoCorrectUrdu = data.autoCorrectUrdu or false
          if data.apiTypingEnabled ~= nil then setApiTypingEnabled(data.apiTypingEnabled) end
          return true
        end
      end
    end
  end
end

function saveAllSettings()
  ensureBackupFolder()
  local allSettings = {
    primary = primaryLangCode, secondary = secondaryLangCode,
    punctuation = settings.punctuation, showLangDialog = settings.showLangDialog,
    autoCorrectUrdu = settings.autoCorrectUrdu, apiTypingEnabled = isApiTypingEnabled()
  }
  local f = io.open(settingsFile, "w")
  if f then
      f:write("return { primary = '"..primaryLangCode.."', secondary = '"..secondaryLangCode.."', punctuation = '"..settings.punctuation.."', showLangDialog = "..tostring(settings.showLangDialog)..", autoCorrectUrdu = "..tostring(settings.autoCorrectUrdu)..", apiTypingEnabled = "..tostring(isApiTypingEnabled()).." }")
      f:close()
  end
end

function applyEndPunctuation(text)
  if settings.punctuation == "none" then return text
  elseif settings.punctuation == "dot_only" then return text:match("[.!?]$") and text or text .. "."
  elseif settings.punctuation == "space_only" then return text:match("%s$") and text or text .. " "
  elseif settings.punctuation == "newline" then return text:match("\n$") and text or text .. "\n" end
  return text
end

-- ============================================================
-- وائس ٹائپنگ لاجک
-- ============================================================
function startVoiceTyping(langCode)
  local speechRec = SpeechRecognizer.createSpeechRecognizer(service.getApplicationContext())
  local listener = RecognitionListener {
    onResults = function(results)
      local res = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if res and res.size() > 0 then
        local rawText = res.get(0)
        
        local function fallback(textToUse)
          local finalText = applyDictionaryReplacements(textToUse or rawText)
          finalText = applyEndPunctuation(finalText)
          service.insertText(service.getEditText(), finalText)
          service.speak(finalText)
        end
        
        if isApiTypingEnabled() then
          processWithAI(rawText, function(aiText)
            if aiText and aiText ~= "" then
              local finalText = applyDictionaryReplacements(aiText)
              finalText = applyEndPunctuation(finalText)
              service.insertText(service.getEditText(), finalText)
              service.speak(finalText)
            else fallback(rawText) end
          end)
        else fallback(rawText) end
      end
      speechRec.destroy()
    end,
    onError = function() speechRec.destroy() end,
  }
  local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, langCode)
  speechRec.setRecognitionListener(listener)
  speechRec.startListening(intent)
end

function showTypingDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Voice Typing")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; text = "Primary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(primaryLangCode) end; };
    { Button; text = "Secondary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(secondaryLangCode) end; };
    { Button; text = "Settings"; layout_width = "fill"; onClick = function() dlg.dismiss(); showMainMenu() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("Digital Typer")
  local views = {}
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "toggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Digital Dictionary"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showDictionaryManager() end; };
    { Button; text = "AI Engine Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() dlg.dismiss() showAISettingsDialog(dlg) end; };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layoutTable, views)
  local function updateUI() views.toggleBtn.setText(settings.showLangDialog and "Show dialog: ON" or "Show dialog: OFF") end
  views.toggleBtn.onClick = function() settings.showLangDialog = not settings.showLangDialog saveAllSettings() updateUI() end
  updateUI()
  dlg.setView(view)
  dlg.show()
end

loadDictionary()
loadAllSettings()

if service.getEditText() then
  if settings.showLangDialog then showTypingDialog() else startVoiceTyping(primaryLangCode) end
else
  showMainMenu()
end
