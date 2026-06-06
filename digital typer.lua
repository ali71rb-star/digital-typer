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
1. STRICT RULE: Every single English word, regardless of how it is written in the input (even if written in Urdu script), MUST be written strictly in the English alphabet/script (e.g., "message", "thank you", "call", "audio", "hi", "ok", "a", "the", "friends"). Under no circumstances should any English word be written or transliterated into Urdu script.
2. Keep Urdu words strictly in Urdu script. Fix any spelling issues or bad word joints in Urdu.
3. CRITICAL URDU RULE: You MUST use the Alif Madda (آ) character for all Urdu words that strictly start with the "aa" sound (e.g., write "آپ", "آج", "آدمی", "آسمان", "آواز", "آسان", "آ رہا", "آ رہی", "آ رہے"). Do NOT write them with a simple Alif (ا).
4. Ensure proper spacing between words.
5. Do NOT add any introductory text, explanation, notes, extra pleasantries, greetings, apologies, or any additional words or sentences.
6. Do NOT add any emojis unless the user explicitly requested them.
7. Return ONLY the exact corrected sentence text output. No extra words before or after the corrected sentence. Do not add "Corrected text:" or any similar prefix. Just the corrected sentence.]]

-- ڈکشنری کی تصحیح کے لیے خصوصی گائیڈ لائن
local DICTIONARY_CORRECTION_INSTRUCTION = [[You are a strict Urdu spelling correction engine. You are given a list of raw words written in Urdu script.
Your absolute assignment is to correct the Urdu spellings of these words inside the Urdu script itself.
CRITICAL LAWS:
1. You MUST output the corrected words strictly in URDU SCRIPT ONLY (e.g., if input is "یکسٹینشن" or "فرینڈ", output "ایکسٹینشن" or "فرینڈز" in Urdu script).
2. CRITICAL ALIF MADDA LAW: Any Urdu word starting with the "aa" sound must be corrected to use Alif Madda (آ) instead of simple Alif (ا).
3. Never convert, translate, or write these words in English characters. Keep them 100% in Urdu text.
4. Maintain the exact sequence and count of words. Do not add commentary, notes, or quotes. Just output space-separated corrected Urdu words.]]

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
            callback(nil, "Gemini Error: " .. status .. "\nPlease verify that your Gemini API Key is correct.") 
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
        elseif status == 401 then callback(nil, "Invalid API key. Please check your Groq API key")
        elseif status == 429 then callback(nil, "Rate limit exceeded. Please wait or check your quota")
        else callback(nil, "Groq Error: " .. status) end
    end)
end

function getGeminiPrompt(spokenText)
    local extra = isEmojiEnabled() and " After each sentence, add ONE relevant emoji." or " Do NOT add any emojis."
    return "Fix this spoken text keeping script languages intact (English words in English characters, Urdu in Urdu characters). Make sure words like aap, aaj, aadmi, aasman, aa raha, aa rahi use Alif Madda (آ):" .. extra .. "\n\nInput Text: " .. spokenText
end

function cleanAIResponse(text)
    if not text then return "" end
    text = text:gsub("^[%s]*Corrected:?%s*", "")
    text = text:gsub("^[%s]*Output:?%s*", "")
    text = text:gsub("^[%s]*Here is the corrected text:?%s*", "")
    text = text:gsub("%s*$", "")
    if text:find("^[A-Z][a-z]+%s+") then
        local firstSentence = text:match("^[^.]+[.]?")
        if firstSentence then text = firstSentence end
    end
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
            groqKeyLabel.setTextColor(0xFFFFFFFF)
            groqKeyLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(groqKeyLabel)
            
            local groqKeyInput = EditText(service)
            groqKeyInput.setHint("Enter Groq API Key")
            local savedGroqKey = getGroqApiKey()
            if savedGroqKey ~= "" then groqKeyInput.setText(savedGroqKey) end
            groqKeyInput.setTextSize(14)
            groqKeyInput.setPadding(20, 15, 20, 15)
            groqKeyInput.setBackgroundColor(0xFF222222)
            local groqKeyParams = LinearLayout.LayoutParams(-1, -2)
            groqKeyParams.setMargins(0, 0, 0, 15)
            groqKeyInput.setLayoutParams(groqKeyParams)
            settingsContainer.addView(groqKeyInput)
            
            local groqModelLabel = TextView(service)
            groqModelLabel.setText("Select Model:")
            groqModelLabel.setTextSize(14)
            groqModelLabel.setTextColor(0xFFFFFFFF)
            groqModelLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(groqModelLabel)
            
            local groqModelSpinner = Spinner(service)
            local groqAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GROQ_MODELS)
            groqAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            groqModelSpinner.setAdapter(groqAdapter)
            local currentGroqModel = getGroqModel()
            for i, m in ipairs(GROQ_MODELS) do
                if m == currentGroqModel then groqModelSpinner.setSelection(i-1) break end
            end
            local groqSpinnerParams = LinearLayout.LayoutParams(-1, -2)
            groqSpinnerParams.setMargins(0, 0, 0, 15)
            groqModelSpinner.setLayoutParams(groqSpinnerParams)
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
            geminiKeyLabel.setTextSize(14)
            geminiKeyLabel.setTextColor(0xFFFFFFFF)
            geminiKeyLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(geminiKeyLabel)
            
            local geminiKeyInput = EditText(service)
            geminiKeyInput.setHint("Enter Gemini API Key")
            local savedGeminiKey = getGeminiApiKey()
            if savedGeminiKey ~= "" then geminiKeyInput.setText(savedGeminiKey) end
            geminiKeyInput.setTextSize(14)
            geminiKeyInput.setPadding(20, 15, 20, 15)
            geminiKeyInput.setBackgroundColor(0xFF222222)
            local geminiKeyParams = LinearLayout.LayoutParams(-1, -2)
            geminiKeyParams.setMargins(0, 0, 0, 15)
            geminiKeyInput.setLayoutParams(geminiKeyParams)
            settingsContainer.addView(geminiKeyInput)
            
            local geminiModelLabel = TextView(service)
            geminiModelLabel.setText("Select Model:")
            geminiModelLabel.setTextSize(14)
            geminiModelLabel.setTextColor(0xFFFFFFFF)
            geminiModelLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(geminiModelLabel)
            
            local geminiModelSpinner = Spinner(service)
            local geminiAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GEMINI_MODELS)
            geminiAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            geminiModelSpinner.setAdapter(geminiAdapter)
            local currentGeminiModel = getGeminiModel()
            for i, m in ipairs(GEMINI_MODELS) do
                if m == currentGeminiModel then geminiModelSpinner.setSelection(i-1) break end
            end
            local geminiSpinnerParams = LinearLayout.LayoutParams(-1, -2)
            geminiSpinnerParams.setMargins(0, 0, 0, 15)
            geminiModelSpinner.setLayoutParams(geminiSpinnerParams)
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
            local selectedEngine = engines[position+1]:lower()
            updateSettingsUI(selectedEngine)
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
    
    local heading = TextView(service)
    heading.setText("Auto Correct Mode")
    heading.setTextSize(16)
    heading.setTextColor(0xFF4CAF50)
    layout.addView(heading)
    
    local description = TextView(service)
    description.setText("About this tool:\n• When API Typing is turned ON, your typed words are automatically saved into the dictionary without any disturbance.\n• When you click Start Correction below, the system will check all saved Urdu words and fix their spelling scripts perfectly one by one.")
    description.setTextSize(14)
    description.setTextColor(0xBBFFFFFF)
    description.setPadding(0, 10, 0, 20)
    layout.addView(description)
    
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
        if not settings.autoCorrectUrdu then 
            service.speak("Auto Correct Disabled")
        else
            service.speak("Auto Correct Enabled")
        end
    end)
    layout.addView(toggleBtn)
    
    local startBtn = Button(service)
    startBtn.setText("Start Correction (Dictionary Process)")
    startBtn.setBackgroundColor(0xFF2196F3)
    local startParams = LinearLayout.LayoutParams(-1, -2)
    startParams.topMargin = 15
    startParams.bottomMargin = 15
    startBtn.setLayoutParams(startParams)
    
    startBtn.setOnClickListener(function()
        if not settings.autoCorrectUrdu then
            service.speak("Your Auto Correct button is OFF. Please turn it ON from the button above before starting correction.")
            return
        end
        
        if isApiTypingEnabled() then
            service.speak("Please disable Typing with API first, then proceed with correction.")
            return
        end
        
        service.speak("Dictionary correction process has started.")
        dlg.dismiss()
        processDictionaryAutoCorrection()
    end)
    layout.addView(startBtn)
    
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
-- درست جوڑوں کی میچنگ اور مینوئل تصحیح لاجک
-- ============================================================
function processDictionaryAutoCorrection()
  local pairsToFix = {}
  for wrong, correct in pairs(changeTable) do
    if wrong:match("[\216-\219]") then
      table.insert(pairsToFix, {wrong = wrong, correct = correct})
    end
  end

  if #pairsToFix == 0 then
    return
  end

  local wrongWordsList = {}
  for _, item in ipairs(pairsToFix) do
    table.insert(wrongWordsList, item.wrong)
  end
  local promptText = table.concat(wrongWordsList, " ")

  local function processAIResult(resultText)
      if not resultText or resultText == "" then return end

      local fixedWords = {}
      for w in resultText:gmatch("%S+") do
        table.insert(fixedWords, w)
      end

      local correctedCount = 0
      local newChangeTable = {}

      for k, v in pairs(changeTable) do
        newChangeTable[k] = v
      end

      local maxLoop = math.min(#pairsToFix, #fixedWords)
      for i = 1, maxLoop do
        local oldWrongUrdu = pairsToFix[i].wrong
        local associatedEnglish = pairsToFix[i].correct
        local newCorrectUrdu = fixedWords[i]

        if oldWrongUrdu ~= newCorrectUrdu and newCorrectUrdu:match("[\216-\219]") then
          newChangeTable[oldWrongUrdu] = nil
          newChangeTable[newCorrectUrdu] = associatedEnglish
          correctedCount = correctedCount + 1
        end
      end

      if correctedCount > 0 then
        changeTable = newChangeTable
        saveDictionary()
        service.speak("Dictionary corrected successfully")
      end
  end

  local engine = getSelectedAIEngine()
  if engine == "groq" then
    local apiKey = getGroqApiKey()
    if not apiKey or apiKey == "" then return end
    local model = getGroqModel()
    callGroqAPI(apiKey, model, DICTIONARY_CORRECTION_INSTRUCTION, promptText, function(result, error)
        if not error then processAIResult(cleanAIResponse(result)) end
    end)
  else
    local apiKey = getGeminiApiKey()
    if not apiKey or apiKey == "" then return end
    local model = getGeminiModel()
    callGeminiAPI(apiKey, model, promptText, DICTIONARY_CORRECTION_INSTRUCTION, function(result, error)
        if not error then processAIResult(cleanAIResponse(result)) end
    end)
  end
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

local languageItems = {}
local languageCodes = {}
for i, lang in ipairs(allLanguages) do
  languageItems[i] = lang.name
  languageCodes[i] = lang.code
end

function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

function copyFile(source, dest)
  local src = File(source)
  local dst = File(dest)
  if src.exists() then
    local inChannel = FileInputStream(src).getChannel()
    local outChannel = FileOutputStream(dst).getChannel()
    inChannel.transferTo(0, inChannel.size(), outChannel)
    inChannel.close()
    outChannel.close()
    return true
  end
  return false
end

function saveDictionary()
  ensureBackupFolder()
  local content = "return " .. dumpTable(changeTable)
  local f = io.open(dictFile, "w")
  if f then
    f:write(content)
    f:close()
    return true
  end
  return false
end

function dumpTable(t, indent)
  indent = indent or 0
  local spaces = string.rep(" ", indent)
  if type(t) == "table" then
    local items = {}
    for k, v in pairs(t) do
      local key = (type(k) == "string" and string.format("%q", k)) or tostring(k)
      table.insert(items, string.format("%s[%s]=%s", spaces, key, dumpTable(v, indent+2)))
    end
    if #items == 0 then return "{}" else
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "}"
    end
  elseif type(t) == "string" then return string.format("%q", t) else return tostring(t) end
end

function escapePattern(str)
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- ============================================================
-- DICTIONARY CORE FUNCTIONS
-- ============================================================
local DICT_CLEARED_KEY = "dict_cleared"

function isDictionaryCleared()
    return sharedPrefs.getBoolean(DICT_CLEARED_KEY, false)
end

function setDictionaryCleared(cleared)
    sharedEditor.putBoolean(DICT_CLEARED_KEY, cleared)
    sharedEditor.commit()
end

function cleanCorruptedDictionaryEntries()
  if not changeTable then return end
  local cleanedTable = {}
  for wrong, correct in pairs(changeTable) do
    if wrong and wrong ~= "" and correct and correct ~= "" then
      cleanedTable[wrong] = correct
    end
  end
  changeTable = cleanedTable
end

function addAlifMaddaWords()
  if isDictionaryCleared() then return end
  local alifMaddaMap = {
    ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
    ["اہ"] = "آہ", ["ارام"] = "آرام", ["azma"] = "آزما", ["باد"] = "آباد",
    ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
    ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے", ["ا رھے"] = "آ رہے"
  }
  for wrong, correct in pairs(alifMaddaMap) do
    if not changeTable[wrong] then
      changeTable[wrong] = correct
    end
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
      local func = loadstring("return " .. content)
      if not func then func = loadstring(content) end
      if func then
        local dict = func()
        if type(dict) == "table" then
          changeTable = dict
          cleanCorruptedDictionaryEntries()
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
    if changeTable[wrongWord] == correctWord then return true end
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

function applyDictionaryReplacements(text)
  if not text or text == "" then return text end
  local result = text
  for wrong, correct in pairs(changeTable) do
    if wrong and wrong ~= "" and correct and correct ~= "" then
      local pattern = "%f[^%s%p]" .. escapePattern(wrong) .. "%f[%s%p\0]"
      local ok, replaced = pcall(function() return result:gsub(pattern, correct) end)
      if ok then result = replaced else
        local patternSimple = escapePattern(wrong)
        result = result:gsub(patternSimple, correct)
      end
    end
  end
  return result
end

function showDictionaryManager()
  local dlg = LuaDialog(service)
  dlg.setTitle("Digital Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { Button; text = "Add Word"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showAddWordDialog() end; };
    { Button; text = "View / Delete Words"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showViewWordsDialog() end; };
    { Button; text = "Auto Correct Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showAutoCorrectMenu() end; };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- صوتی مماثلت کا فنکشن (سپورٹ کے لیے)
-- ============================================================
function checkPhoneticMatch(uWord, eWord)
  if not uWord or not eWord or uWord == "" or eWord == "" then return false end
  local uFirst = uWord:match("^([\216-\219][\128-\191])")
  if not uFirst then return false end
  local eFirst = eWord:sub(1,1):lower()
  
  local uToE = {
    ["و"] = {w = true, v = true, o = true, u = true},
    ["ٹ"] = {t = true}, ["ت"] = {t = true}, ["ط"] = {t = true},
    ["ک"] = {k = true, c = true, q = true}, ["گ"] = {g = true},
    ["م"] = {m = true}, ["ف"] = {f = true, p = true},
    ["ب"] = {b = true}, ["پ"] = {p = true},
    ["ڈ"] = {d = true}, ["د"] = {d = true}, ["ر"] = {r = true},
    ["ل"] = {l = true}, ["ن"] = {n = true}, ["ہ"] = {h = true}, ["ح"] = {h = true},
    ["ج"] = {j = true, g = true}, ["چ"] = {c = true},
    ["س"] = {s = true, c = true}, ["ص"] = {s = true}, ["ث"] = {s = true}, ["ش"] = {s = true},
    ["ز"] = {z = true}, ["ذ"] = {z = true}, ["ض"] = {z = true}, ["ظ"] = {z = true},
    ["ی"] = {y = true, e = true, i = true},
    ["ا"] = {a = true, e = true, i = true, o = true, u = true},
    ["آ"] = {a = true, e = true, i = true, o = true, u = true},
  }
  if uToE[uFirst] and uToE[uFirst][eFirst] then return true end
  return false
end

-- ============================================================
-- فکسڈ لرننگ لاجک (اینکرز اور سمارٹ پوزیشن الائنمنٹ کے ساتھ)
-- ============================================================
function learnFromAI(rawText, aiText, silent)
  silent = true 
  if not rawText or not aiText then return end

  local function clean(w)
    if not w then return "" end
    local last_w
    repeat
      last_w = w
      w = w:gsub("^[%p%s]", ""):gsub("[%p%s]$", "")
      w = w:gsub("^۔", ""):gsub("^،", "")
      w = w:gsub("۔$", ""):gsub("،$", "")
    until w == last_w
    return w
  end

  local rawWords = {}
  for w in rawText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" then table.insert(rawWords, cw) end
  end

  local aiWords = {}
  for w in aiText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" then table.insert(aiWords, cw) end
  end

  if #rawWords == 0 or #aiWords == 0 then return end

  local rawAnchored = {}
  local aiAnchored = {}
  
  for i = 1, #rawWords do
    for j = 1, #aiWords do
      if not aiAnchored[j] and rawWords[i] == aiWords[j] then
        if math.abs(i - j) <= 3 then
          rawAnchored[i] = j
          aiAnchored[j] = i
          break
        end
      end
    end
  end

  for i = 1, #rawWords do
    if not rawAnchored[i] then
      local rw = rawWords[i]
      local bestJ = nil
      local minDistance = 999
      
      local startLook = math.max(1, i - 2)
      local endLook = math.min(#aiWords, i + 2)
      
      for j = startLook, endLook do
        if not aiAnchored[j] then
          local aw = aiWords[j]
          if checkPhoneticMatch(rw, aw) then
            bestJ = j
            break
          end
          local dist = math.abs(i - j)
          if dist < minDistance then
            minDistance = dist
            bestJ = j
          end
        end
      end
      
      if bestJ then
        local aw = aiWords[bestJ]
        if rw ~= aw and not (rw:match("^[a-zA-Z]+$") and aw:match("^[a-zA-Z]+$")) then
          if changeTable[rw] ~= aw then
            addToDictionary(rw, aw)
          end
          aiAnchored[bestJ] = i
          rawAnchored[i] = bestJ
        end
      end
    end
  end

  local alifMaddaWords = {
    ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
    ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
    ["انسو"] = "آنسو", ["اخری"] = "آخری", ["واز"] = "آواز", ["انکھیں"] = "آنکھیں",
    ["اداب"] = "آداب", ["اسان"] = "آسان", ["ام"] = "آام", ["ایت"] = "آیت",
    ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
    ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے", ["ا رھے"] = "آ رہے"
  }
  for i = 1, #rawWords do
    local word = rawWords[i]
    if alifMaddaWords[word] then
      if changeTable[word] ~= alifMaddaWords[word] then
        addToDictionary(word, alifMaddaWords[word])
      end
    end
  end
end

-- ============================================================
-- ایڈ اور ویو ورڈز ڈائیلاگ (آئی ڈی فکسڈ برائے سیونگ)
-- ============================================================
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
            if addToDictionary(w, c) then
              service.speak("Saved successfully")
              dlg.dismiss()
            else
              service.speak("Failed to save.")
            end
          else
            service.speak("Fields cannot be empty")
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
  
  local function rebuildList()
    wordsList.clear()
    table.clear(rawKeys)
    for k, v in pairs(changeTable) do
      table.insert(rawKeys, k)
      wordsList.add(tostring(k) .. " -> " .. tostring(v)) 
    end
  end
  
  rebuildList()
  local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, wordsList)
  list.setAdapter(adapter)
  
  list.setOnItemClickListener(function(parent, view, position, id)
    local selectedKey = rawKeys[position+1]
    local askDlg = LuaDialog(service)
    askDlg.setTitle("Delete Entry")
    askDlg.setMessage("Do you want to delete this word replacement?")
    askDlg.setButton("Delete", function()
      deleteFromDictionary(selectedKey)
      service.speak("Deleted")
      askDlg.dismiss()
      adapter.clear()
      adapter.notifyDataSetChanged()
      dlg.dismiss() 
      showViewWordsDialog()
    end)
    askDlg.setButton2("Cancel", function() askDlg.dismiss() end)
    askDlg.show()
  end)
  
  dlg.setButton("Empty", function()
    local confirmDlg = LuaDialog(service)
    confirmDlg.setTitle("Clear All")
    confirmDlg.setMessage("Are you sure you want to clear the entire dictionary?")
    confirmDlg.setButton("Clear All", function()
      clearAllDictionary()
      service.speak("Dictionary cleared completely")
      confirmDlg.dismiss()
      adapter.clear()
      adapter.notifyDataSetChanged()
      dlg.dismiss() 
      showViewWordsDialog()
    end)
    confirmDlg.setButton2("Cancel", function() confirmDlg.dismiss() end)
    confirmDlg.show()
  end)
  
  dlg.setButton2("Close", function() dlg.dismiss() end)
  dlg.setView(list)
  dlg.show()
end

function getLanguageNameFromCode(code)
  for _, lang in ipairs(allLanguages) do
    if lang.code == code then return lang.name end
  end
  return code
end

function showLanguagePicker(callback)
  local dlg = LuaDialog(service)
  dlg.setTitle("Select Language")
  local list = ListView(service)
  local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, languageItems)
  list.setAdapter(adapter)
  list.setOnItemClickListener(function(parent, view, position, id)
    local selectedCode = languageCodes[position+1]
    local selectedName = languageItems[position+1]
    callback(selectedCode, selectedName)
    service.speak("Selected " .. selectedName)
    dlg.dismiss()
  end)
  dlg.setView(list)
  dlg.show()
end

function showBackupRestoreDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Backup / Restore")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { Button; text = "Backup Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupDictionary() end; };
    { Button; text = "Backup Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupSettings() end; };
    { Button; text = "Restore Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        if copyFile(dictBackupFile, dictFile) then
          setDictionaryCleared(false)
          loadDictionary()
          service.speak("Dictionary restored successfully")
        else
          service.speak("No backup found")
        end
      end;
    };
    { Button; text = "Restore Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        if copyFile(settingsBackupFile, settingsFile) then
          loadAllSettings()
          service.speak("Settings restored successfully")
        else
          service.speak("No backup found")
        end
      end;
    };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function loadAllSettings()
  local f = io.open(settingsFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      content = content:gsub("^\239\187\191", "")
      local func = loadstring(content)
      if func then
        local data = func()
        if type(data) == "table" then
          primaryLangCode = data.primary or "en-PK"
          secondaryLangCode = data.secondary or "ur-PK"
          favouriteIndices = data.favourites or {}
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.autoCorrectUrdu = data.autoCorrectUrdu or false
          if data.apiTypingEnabled ~= nil then
            setApiTypingEnabled(data.apiTypingEnabled)
          end
          return true
        end
      end
    end
  end
  return false
end

function saveAllSettings()
  ensureBackupFolder()
  local allSettings = {
    primary = primaryLangCode,
    secondary = secondaryLangCode,
    favourites = favouriteIndices,
    punctuation = settings.punctuation,
    showLangDialog = settings.showLangDialog,
    autoCorrectUrdu = settings.autoCorrectUrdu,
    apiTypingEnabled = isApiTypingEnabled()
  }
  local content = "return " .. dumpTable(allSettings)
  local f = io.open(settingsFile, "w")
  if f then
    f:write(content)
    f:close()
    return true
  end
  return false
end

function applyEndPunctuation(text)
  if settings.punctuation == "none" then return text
  elseif settings.punctuation == "dot_only" then
    if not text:match("[.!?]$") then return text .. "." end
  elseif settings.punctuation == "space_only" then
    if not text:match("%s$") then return text .. " " end
  elseif settings.punctuation == "newline" then
    if not text:match("\n$") then return text .. "\n" end
  end
  return text
end

function showPunctuationDialog()
    local dlg = LuaDialog(service)
    dlg.setTitle("Punctuation Settings")
    local options = {"None", "Dot Only (.)", "Space Only ( )", "New Line (\\n)"}
    local codes = {"none", "dot_only", "space_only", "newline"}
    local currentCode = settings.punctuation or "newline"
    local currentIndex = 0
    for i, code in ipairs(codes) do
        if code == currentCode then currentIndex = i - 1 break end
    end
    
    local spinner = Spinner(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, options)
    adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    spinner.setAdapter(adapter) 
    spinner.setSelection(currentIndex)
    
    local layout = LinearLayout(service)
    layout.setOrientation(1)
    layout.setPadding(40, 30, 40, 30)
    
    local heading = TextView(service)
    heading.setText("Choose punctuation style:")
    heading.setTextSize(16)
    heading.setTextColor(0xFFFFFFFF)
    heading.setPadding(0, 0, 0, 20)
    layout.addView(heading)
    layout.addView(spinner)
    
    local saveBtn = Button(service)
    saveBtn.setText("Save")
    saveBtn.setTextSize(14)
    saveBtn.setBackgroundColor(0xFF4CAF50)
    saveBtn.setPadding(0, 15, 0, 15)
    local btnParams = LinearLayout.LayoutParams(-1, -2)
    btnParams.topMargin = 30
    saveBtn.setLayoutParams(btnParams)
    layout.addView(saveBtn)
    
    saveBtn.setOnClickListener(function()
        local selectedPos = spinner.getSelectedItemPosition()
        settings.punctuation = codes[selectedPos + 1]
        saveAllSettings()
        service.speak("Punctuation set to " .. options[selectedPos + 1])
        dlg.dismiss()
    end)
    
    dlg.setView(layout)
    dlg.show()
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
          local finalText = textToUse or rawText
          if langCode ~= secondaryLangCode then
            learnFromAI(rawText, finalText, true)
          end
          
          local alifMaddaMap = {
            ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
            ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
            ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
            ["انسو"] = "آنسو", ["اخری"] = "آخری", ["واز"] = "آواز", ["انکھیں"] = "آنکھیں",
            ["اداب"] = "آداب", ["اسان"] = "آسان", ["ام"] = "آام", ["ایت"] = "آیت",
            ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
            ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے", ["ا رھے"] = "آ رہے"
          }
          for wrong, correct in pairs(alifMaddaMap) do
             finalText = finalText:gsub("%f[^%s%p]" .. escapePattern(wrong) .. "%f[%s%p\0]", correct)
          end
          
          finalText = applyDictionaryReplacements(finalText)
          finalText = applyEndPunctuation(finalText)
          service.insertText(service.getEditText(), finalText)
          service.speak(finalText)
        end
        
        if isApiTypingEnabled() then
          processWithAI(rawText, function(aiText)
            if aiText and aiText ~= "" then
              if langCode ~= secondaryLangCode then
                learnFromAI(rawText, aiText, true)
              end
              
              local alifMaddaMap = {
                ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
                ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
                ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
                ["انسو"] = "آنسو", ["اخری"] = "آخری", ["واز"] = "آواز", ["انکھیں"] = "آنکھیں",
                ["اداب"] = "آداب", ["اسان"] = "آسان", ["ام"] = "آام", ["ایت"] = "آیت",
                ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
                ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے", ["ا rھے"] = "آ رہے"
              }
              for wrong, correct in pairs(alifMaddaMap) do
                 aiText = aiText:gsub("%f[^%s%p]" .. escapePattern(wrong) .. "%f[%s%p\0]", correct)
              end
              
              local finalText = applyDictionaryReplacements(aiText)
              finalText = applyEndPunctuation(finalText)
              service.insertText(service.getEditText(), finalText)
              service.speak(finalText)
            else
              fallback(rawText)
            end
          end)
        else
          fallback(rawText)
        end
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

function checkAutoCorrectAndProceed(langCode, currentDlg)
    if settings.autoCorrectUrdu then
        service.speak("Auto Correct is enabled. Please disable it before typing.")
        local alert = LuaDialog(service)
        alert.setTitle("Auto Correct Warning")
        alert.setMessage("Voice Typing cannot start while Auto Correct is ON. Please go to settings and turn it OFF.")
        alert.setButton("Go to Auto Correct Settings", function()
            alert.dismiss()
            currentDlg.dismiss()
            showAutoCorrectMenu(currentDlg)
        end)
        alert.setButton2("Cancel", function() alert.dismiss() end)
        alert.show()
    else
        currentDlg.dismiss()
        startVoiceTyping(langCode)
    end
end

function showTypingDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Voice Typing")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; text = "Primary (" .. getLanguageNameFromCode(primaryLangCode) .. ")"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() checkAutoCorrectAndProceed(primaryLangCode, dlg) end; };
    { Button; text = "Swap Languages"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        local temp = primaryLangCode
        primaryLangCode = secondaryLangCode
        secondaryLangCode = temp
        saveAllSettings()
        dlg.dismiss()
        showTypingDialog()
      end;
    };
    { Button; text = "Secondary (" .. getLanguageNameFromCode(secondaryLangCode) .. ")"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() checkAutoCorrectAndProceed(secondaryLangCode, dlg) end; };
    { Button; text = "Settings"; layout_width = "fill"; onClick = function() dlg.dismiss(); showMainMenu() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- مین مینو (آئی ڈی فکسڈ)
-- ============================================================
function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("digital typer")
  local views = {}
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "toggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Set Primary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) primaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Set Secondary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) secondaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Digital Dictionary"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showDictionaryManager() end; };
    { Button; text = "Punctuation Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showPunctuationDialog() end; };
    { Button; text = "AI Engine Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() dlg.dismiss() showAISettingsDialog(dlg) end; };
    { Button; text = "Backup / Restore"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showBackupRestoreDialog() end; };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layoutTable, views)
  local function updateUI() views.toggleBtn.setText(settings.showLangDialog and "Show dialog: ON" or "Show dialog: OFF") end
  views.toggleBtn.onClick = function() settings.showLangDialog = not settings.showLangDialog saveAllSettings() updateUI() end
  updateUI()
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- Entry Point
-- ============================================================
loadDictionary()
loadAllSettings()

if service.getEditText() then
  if settings.showLangDialog then 
    showTypingDialog() 
  else 
    if settings.autoCorrectUrdu then
        showTypingDialog()
    else
        startVoiceTyping(primaryLangCode) 
    end
  end
else
  showMainMenu()
end