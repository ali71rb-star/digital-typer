require "import"
import "android.widget.*"
import "android.content.Intent"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"
import "android.content.Context"
import "java.io.File"
import "android.os.Environment"

-- ============================================================
-- فائل راستے (صرف سیٹنگز سیو کرنے کے لیے)
-- ============================================================
local backupFolder = os.getenv("EXTERNAL_STORAGE") .. "/解说/Plugins/digital typer/backup"
local settingsFile = backupFolder .. "/digital_typer_settings.txt"

-- سیٹنگز
local settings = { 
    punctuation = "newline", 
    showLangDialog = true, 
    offlineModeEnabled = false -- (By default OFF)
}
local primaryLangCode = "ur-PK"
local secondaryLangCode = "en-PK"

function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

-- ============================================================
-- 100% ایکوریٹ بلٹ اِن ڈکشنری (کوڈ کے اندر ہی)
-- ============================================================
-- یہ وہ لسٹ ہے جو بغیر انٹرنیٹ کے کام کرے گی۔ "اپنے"، "اپنا"، "امید" اس میں نہیں ہیں تاکہ وہ الف سے ہی لکھے جائیں۔
local offlineAlifMaddaTable = {
    ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
    ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
    ["انسو"] = "آنسو", ["اخری"] = "آخری", ["اواز"] = "آواز", ["انکھیں"] = "آنکھیں",
    ["انکھ"] = "آنکھ", ["اداب"] = "آداب", ["اسان"] = "آسان", ["ام"] = "آم", 
    ["ایت"] = "آیت", ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", 
    ["ارھے"] = "آرہے", ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے",
    ["ازاد"] = "آزاد", ["ازادی"] = "آزادی", ["اسپاس"] = "آس پاس", ["ایندہ"] = "آئندہ", 
    ["اغاز"] = "آغاز", ["ابادی"] = "آبادی", ["الو"] = "آلو", ["امدن"] = "آمدن", 
    ["امدی"] = "آمدی", ["اڑو"] = "آڑو", ["اری"] = "آری", ["اہستہ"] = "آہستہ", 
    ["اخر"] = "آخر", ["ادھا"] = "آدھا", ["ادھے"] = "آدھے", ["ادھی"] = "آدھی",
    ["اشنا"] = "آشنا", ["اغوش"] = "آغوش", ["الہ"] = "آلہ", ["اموز"] = "آموز", 
    ["انچ"] = "آنچ", ["اندھی"] = "آندھی", ["انگن"] = "آنگن", ["اہٹ"] = "آہٹ", 
    ["ائینہ"] = "آئینہ", ["اخرکار"] = "آخرکار", ["ابشار"] = "آبشار", ["ابرو"] = "آبرو", 
    ["ازمانا"] = "آزمانا", ["ازمائش"] = "آزمائش", ["اسرہ"] = "آسرہ", ["اسودہ"] = "آسودہ", 
    ["اغیار"] = "آغیار", ["الودہ"] = "آلودہ", ["امنے"] = "آمنے", ["اوارہ"] = "آوارہ", 
    ["اہن"] = "آہن", ["ایات"] = "آیات", ["امادہ"] = "آمادہ", ["اراستہ"] = "آراستہ", 
    ["ازردہ"] = "آزردہ", ["اسیہ"] = "آسیہ", ["اثار"] = "آثار", ["ادھ"] = "آدھ", 
    ["افات"] = "آفات", ["اقا"] = "آقا", ["الات"] = "آلات", ["امیز"] = "آمیز", 
    ["اواگون"] = "آواگون", ["اویزاں"] = "آویزاں", ["استین"] = "آستین", ["اسیب"] = "آسیب"
}

-- ============================================================
-- SUPER ACCURATE OFFLINE ENGINE (Space Padding Algorithm)
-- ============================================================
function processOfflineUrduText(rawText)
    -- اگر آف لائن پروسیسنگ آپشن OFF ہے، تو بغیر کسی تبدیلی کے اصل ٹیکسٹ واپس کر دیں
    if not settings.offlineModeEnabled then 
        return rawText 
    end
    
    if not rawText or rawText == "" then return rawText end
    
    local text = rawText
    
    -- سٹیپ 1: رموزِ اوقاف (Punctuation) کے ارد گرد اسپیس دیں تاکہ وہ الفاظ کے ساتھ نہ جڑیں
    text = text:gsub("([۔،؟!.])", " %1 ")
    
    -- سٹیپ 2: پورے ٹیکسٹ کے شروع اور آخر میں اسپیس لگائیں (Boundary Protection)
    text = " " .. text .. " "
    
    -- سٹیپ 3: ڈکشنری چیک کر کے پرفیکٹ ورڈ ریپلیسمنٹ
    for wrong, correct in pairs(offlineAlifMaddaTable) do
        local pattern = "%s" .. wrong .. "%s"
        local replacement = " " .. correct .. " "
        
        -- دو بار رن کیا گیا ہے تاکہ اگر دو غلط الفاظ ساتھ ساتھ ہوں تو مس نہ ہوں
        text = text:gsub(pattern, replacement)
        text = text:gsub(pattern, replacement) 
    end
    
    -- سٹیپ 4: فالتو اسپیس ختم کریں اور کلین کریں
    text = text:gsub("%s+", " ") -- ایک سے زیادہ اسپیس کو ایک کر دے گا
    text = text:gsub(" ([۔،؟!.])", "%1") -- پنکچویشن سے پہلے والی اسپیس ہٹا دے گا
    text = text:match("^%s*(.-)%s*$") -- شروع اور آخر کی اسپیس ختم
    
    return text
end

-- ============================================================
-- سیٹنگز سیو اور لوڈ کرنے کا نظام
-- ============================================================
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
          primaryLangCode = data.primary or "ur-PK"
          secondaryLangCode = data.secondary or "en-PK"
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.offlineModeEnabled = data.offlineModeEnabled or false
          return true
        end
      end
    end
  end
end

function saveAllSettings()
  ensureBackupFolder()
  local f = io.open(settingsFile, "w")
  if f then
      local content = string.format(
          "return { primary = %q, secondary = %q, punctuation = %q, showLangDialog = %s, offlineModeEnabled = %s }",
          primaryLangCode, secondaryLangCode, settings.punctuation, 
          tostring(settings.showLangDialog), tostring(settings.offlineModeEnabled)
      )
      f:write(content)
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
        
        -- ہمارا نیا سمارٹ آف لائن انجن کال ہو رہا ہے
        local finalText = processOfflineUrduText(rawText)
        finalText = applyEndPunctuation(finalText)
        
        service.insertText(service.getEditText(), finalText)
        service.speak(finalText)
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
    { Button; text = "Primary (Urdu)"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(primaryLangCode) end; };
    { Button; text = "Secondary (English)"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(secondaryLangCode) end; };
    { Button; text = "Settings"; layout_width = "fill"; onClick = function() dlg.dismiss(); showMainMenu() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- مین مینو (ڈائیلاگ اور آف لائن موڈ ٹوگل کے ساتھ)
-- ============================================================
function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("Digital Typer Settings")
  local views = {}
  
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "offlineToggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; id = "dialogToggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  
  local view = loadlayout(layoutTable, views)
  
  local function updateUI() 
      views.dialogToggleBtn.setText(settings.showLangDialog and "Show Language Dialog: ON" or "Show Language Dialog: OFF") 
      views.offlineToggleBtn.setText(settings.offlineModeEnabled and "Use Without Internet (Auto-Correct): ON" or "Use Without Internet (Auto-Correct): OFF") 
      
      -- آف لائن بٹن کا رنگ
      if settings.offlineModeEnabled then
          views.offlineToggleBtn.setBackgroundColor(0xFF4CAF50) -- Green (ON)
      else
          views.offlineToggleBtn.setBackgroundColor(0xFFF44336) -- Red (OFF)
      end
  end
  
  views.dialogToggleBtn.onClick = function() 
      settings.showLangDialog = not settings.showLangDialog 
      saveAllSettings() 
      updateUI() 
  end
  
  views.offlineToggleBtn.onClick = function() 
      settings.offlineModeEnabled = not settings.offlineModeEnabled 
      saveAllSettings() 
      updateUI() 
      
      if settings.offlineModeEnabled then
          service.speak("Offline Auto Correct Enabled")
      else
          service.speak("Offline Auto Correct Disabled")
      end
  end
  
  updateUI()
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- Entry Point
-- ============================================================
ensureBackupFolder()
loadAllSettings()

if service.getEditText() then
  if settings.showLangDialog then 
      showTypingDialog() 
  else 
      startVoiceTyping(primaryLangCode) 
  end
else
  showMainMenu()
end
