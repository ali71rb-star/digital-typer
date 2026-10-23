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
    offlineModeEnabled = false
}
local primaryLangCode = "ur-PK"
local secondaryLangCode = "en-PK"

function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

-- ============================================================
-- انتہائی جامع اور پاور فل بلٹ اِن ڈکشنری (No External File Needed)
-- ============================================================
-- اس لسٹ میں وہ تمام الفاظ ہیں جو الف مدہ (آ) سے شروع ہوتے ہیں لیکن گوگل انہیں (ا) سے لکھتا ہے۔
-- سمارٹ انجن کی وجہ سے یہ "اپنا", "اپنے", "امید", "انسان" جیسے الفاظ کو ہرگز خراب نہیں کرے گا۔
local offlineAlifMaddaTable = {
    -- عام استعمال کے الفاظ / Pronouns & Basics
    ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["اواز"] = "آواز",
    ["انکھیں"] = "آنکھیں", ["انکھ"] = "آنکھ", ["اسان"] = "آسان", ["ام"] = "آم",
    ["الو"] = "آلو", ["اڑو"] = "آڑو", ["اری"] = "آری", ["اہستہ"] = "آہستہ",
    ["اخر"] = "آخر", ["اخرکار"] = "آخرکار", ["ادھا"] = "آدھا", ["ادھے"] = "آدھے", 
    ["ادھی"] = "آدھی", ["ازاد"] = "آزاد", ["ازادی"] = "آزادی", ["اسپاس"] = "آس پاس", 
    
    -- فعل اور ان کی حالتیں (Verbs & Forms)
    ["ایا"] = "آیا", ["ائے"] = "آئے", ["ائی"] = "آئی", ["اؤ"] = "آؤ", 
    ["اکر"] = "آکر", ["اتے"] = "آتے", ["اتی"] = "آتی", ["اتا"] = "آتا",
    ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے", 
    ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے",
    ["ازمانا"] = "آزمانا", ["ازمائش"] = "آزمائش", ["ازما"] = "آزما",
    
    -- اسم اور صفات (Nouns & Adjectives)
    ["استان"] = "آستان", ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", 
    ["ابادی"] = "آبادی", ["افت"] = "آفت", ["افات"] = "آفات", ["انسو"] = "آنسو", 
    ["اخری"] = "آخری", ["اداب"] = "آداب", ["ایت"] = "آیت", ["ایات"] = "آیات",
    ["ایندہ"] = "آئندہ", ["اغاز"] = "آغاز", ["امدن"] = "آمدن", ["امدی"] = "آمدی", 
    ["اشنا"] = "آشنا", ["اغوش"] = "آغوش", ["الہ"] = "آلہ", ["الات"] = "آلات",
    ["اموز"] = "آموز", ["اموزش"] = "آموزش", ["انچ"] = "آنچ", ["اندھی"] = "آندھی", 
    ["انگن"] = "آنگن", ["اہٹ"] = "آہٹ", ["ائینہ"] = "آئینہ", ["ائین"] = "آئین",
    ["ابشار"] = "آبشار", ["ابرو"] = "آبرو", ["اسرہ"] = "آسرہ", ["اسودہ"] = "آسودہ", 
    ["اغیار"] = "آغیار", ["الودہ"] = "آلودہ", ["امنے"] = "آمنے", ["اوارہ"] = "آوارہ", 
    ["اہن"] = "آہن", ["امادہ"] = "آمادہ", ["اراستہ"] = "آراستہ", ["ازردہ"] = "آزردہ", 
    ["اثار"] = "آثار", ["ادھ"] = "آدھ", ["اقا"] = "آقا", ["اقاؤں"] = "آقاؤں", 
    ["امیز"] = "آمیز", ["اواگون"] = "آواگون", ["اویزاں"] = "آویزاں", ["استین"] = "آستین", 
    ["اسیب"] = "آسیب", ["ارزو"] = "آرزو", ["ارزومند"] = "آرزومند", ["ازار"] = "آزار",
    ["ازردگی"] = "آزردگی", ["اسامی"] = "آسامی", ["اسامیاں"] = "آسامیاں", ["اسانی"] = "آسانی",
    ["اشام"] = "آشام", ["اشکار"] = "آشکار", ["اشکارا"] = "آشکارا", ["اشوب"] = "آشوب",
    ["افاقہ"] = "آفاقہ", ["اگاہ"] = "آگاہ", ["اگاہی"] = "آگاہی", ["الاپ"] = "آلاپ",
    ["اماجگاہ"] = "آماجگاہ", ["امادگی"] = "آمادگی", ["امیزش"] = "آمیزش", ["انچوں"] = "آنچوں",
    ["اندھیاں"] = "آندھیاں", ["انولہ"] = "آنولہ", ["اہٹیں"] = "آہٹیں", ["اہو"] = "آہو",
    ["اڑھائی"] = "آڑھائی", ["ارزاں"] = "آرزاں",
    
    -- نام (Names)
    ["اسیہ"] = "آسیہ", ["امنہ"] = "آمنہ", ["اصف"] = "آصف", ["اصفہ"] = "آصفہ", 
    ["افاق"] = "آفاق", ["افتاب"] = "آفتاب", ["ادم"] = "آدم", ["ازر"] = "آزر", 
    ["ارمین"] = "آرمین"
}

-- ============================================================
-- SUPER ACCURATE OFFLINE ENGINE (Space Padding Algorithm)
-- ============================================================
function processOfflineUrduText(rawText)
    -- آف لائن پروسیسنگ آپشن چیک کریں
    if not settings.offlineModeEnabled then 
        return rawText 
    end
    
    if not rawText or rawText == "" then return rawText end
    
    local text = rawText
    
    -- رموزِ اوقاف اور لائن بریک کو اسپیس کے ساتھ الگ کریں تاکہ الفاظ نہ جڑیں
    text = text:gsub("([۔،؟!.%\n])", " %1 ")
    
    -- باؤنڈری پروٹیکشن کے لیے شروع اور آخر میں اسپیس
    text = " " .. text .. " "
    
    -- طاقتور ڈکشنری اپلائی کریں
    for wrong, correct in pairs(offlineAlifMaddaTable) do
        local pattern = "%s" .. wrong .. "%s"
        local replacement = " " .. correct .. " "
        
        -- ڈبل رن (Double Run) سے ساتھ ساتھ جڑے غلط الفاظ بھی پکڑے جاتے ہیں
        text = text:gsub(pattern, replacement)
        text = text:gsub(pattern, replacement) 
    end
    
    -- فالتو اسپیسز اور باؤنڈریز کی صفائی
    text = text:gsub("%s+", " ")
    text = text:gsub(" ([۔،؟!.%\n])", "%1")
    text = text:match("^%s*(.-)%s*$")
    
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
        
        -- خودکار آف لائن انجن کالنگ
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
      
      if settings.offlineModeEnabled then
          views.offlineToggleBtn.setBackgroundColor(0xFF4CAF50) -- Green
      else
          views.offlineToggleBtn.setBackgroundColor(0xFFF44336) -- Red
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
