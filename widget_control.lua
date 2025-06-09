obs = obslua

local json = require("json") 

local bit = require("bit")


local function url_encode(str)
  if not str then return "" end
  str = tostring(str)
  str = string.gsub(str, "([^%w%._%- ])", function(c)
      return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "%%20")
  return str
end


local function int_to_css_color(color_int)
  local a = bit.rshift(bit.band(color_int, 0xFF000000), 24)
  local r = bit.rshift(bit.band(color_int, 0x00FF0000), 16)
  local g = bit.rshift(bit.band(color_int, 0x0000FF00), 8)
  local b = bit.band(color_int, 0x000000FF)
  if a < 255 then
    return string.format("rgba(%d,%d,%d,%.2f)", r, g, b, a / 255)
  else
    return string.format("#%02x%02x%02x", r, g, b)
  end
end


local function css_color_to_int(css_str)
  if not css_str then return 0xFF000000 end 
  local r, g, b, a
  local _, _, r_str, g_str, b_str, a_str = string.find(css_str, "rgba%((%d+),%s*(%d+),%s*(%d+),%s*([%d%.]+)%)")
  if r_str then
    r = tonumber(r_str)
    g = tonumber(g_str)
    b = tonumber(b_str)
    a = math.floor(tonumber(a_str) * 255)
  else  
    _, _, r_str, g_str, b_str = string.find(css_str, "rgb%((%d+),%s*(%d+),%s*(%d+)%)")
    if r_str then
      r = tonumber(r_str)
      g = tonumber(g_str)
      b = tonumber(b_str)
      a = 255 
    else
  
      local hex_r, hex_g, hex_b = css_str:match("#(%x%x)(%x%x)(%x%x)")
      if hex_r then
        r = tonumber(hex_r, 16)
        g = tonumber(hex_g, 16)
        b = tonumber(hex_b, 16)
        a = 255 
      else
        obs.log(obs.LOG_WARNING, "Неизвестный формат цвета CSS: " .. css_str .. ". Использование черного непрозрачного.")
        return 0xFF000000
      end
    end
  end


  r = math.max(0, math.min(255, r))
  g = math.max(0, math.min(255, g))
  b = math.max(0, math.min(255, b))
  a = math.max(0, math.min(255, a))

  return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
end


local config = {
  widget_url = "",
  wins = 0,
  losses = 0,
  rank = 0,
  bg_type = "color",
  bg_color = "rgba(0,0,0,0.7)", 
  bg_image = "",
  font = "Arial", 
  font_size = 16,
  wins_color = "#00ff00",
  losses_color = "#ff0000",
  rank_text_color = "#ffffff",
  anim_direction = "left",
  anim_duration_in = 500,
  anim_stay_time = 10000,
  anim_duration_out = 500,
  hidden_time = 8000,
  auto_create_source = true
}

-- Генерация списка рангов
local ranks = {}
local rank_types = {"Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master", "Grandmaster", "Champion"}
for _, type in ipairs(rank_types) do
  for level = 5, 1, -1 do
    table.insert(ranks, {name = type .. " " .. level, value = #ranks})
  end
end
-- Top 500 рангов
for level = 500, 1, -1 do
  table.insert(ranks, {name = "Top " .. level, value = #ranks})
end

local shouldResetLocalStorage = false
local widget_source = nil 
local frontend_event_callback_id = nil 

-- ID горячих клавиш
local hotkey_increase_wins_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_increase_losses_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_increase_rank_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_decrease_rank_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_reset_stats_id = obs.OBS_INVALID_HOTKEY_ID

-- Поиск источника виджета
function find_widget_source()
  local source = obs.obs_get_source_by_name("Widget Stats")
  if source then
    return source
  end
  return nil
end

-- Создание источника виджета
function create_widget_source()
  obs.script_log(obs.LOG_INFO, "Попытка создания источника 'Widget Stats'...")
  local current_scene_source = obs.obs_frontend_get_current_scene()
  if not current_scene_source then
    obs.script_log(obs.LOG_WARNING, "Не удалось получить текущую сцену. Убедитесь, что OBS полностью загружен и активна хотя бы одна сцена.")
    return nil
  end

  local scene = obs.obs_scene_from_source(current_scene_source)
  local source_settings = obs.obs_data_create()
  obs.obs_data_set_string(source_settings, "url", config.widget_url) -- Изначально пустой URL
  obs.obs_data_set_int(source_settings, "width", 470) -- Ширина по умолчанию
  obs.obs_data_set_int(source_settings, "height", 100) -- Высота по умолчанию
  obs.obs_data_set_bool(source_settings, "shutdown", true)
  obs.obs_data_set_bool(source_settings, "restart_when_active", true)

  local new_source = obs.obs_source_create("browser_source", "Widget Stats", source_settings, nil)
  if new_source then
    obs.obs_scene_add(scene, new_source)
    obs.script_log(obs.LOG_INFO, "Источник 'Widget Stats' успешно создан.")
  else
    obs.script_log(obs.LOG_WARNING, "Не удалось создать источник 'Widget Stats'.")
  end

  obs.obs_data_release(source_settings)
  obs.obs_scene_release(scene)
  obs.obs_source_release(current_scene_source)
  return new_source
end

function update_widget_source_base_url()
  if not widget_source then
    widget_source = find_widget_source() 
  end

  if not widget_source then
    obs.script_log(obs.LOG_WARNING, "Не могу обновить URL: источник 'Widget Stats' не найден.")
    return
  end
  
  local base_url = config.widget_url
  local cache_buster_param = "_t=" .. tostring(os.time())
  local reset_param = ""
  if shouldResetLocalStorage then
    reset_param = "&resetConfig=1"
    shouldResetLocalStorage = false
  end
  local full_url = base_url .. (string.find(base_url, "?") and "&" or "?") .. cache_buster_param .. reset_param

  local settings_source = obs.obs_source_get_settings(widget_source) 
  if settings_source then
    obs.obs_data_set_string(settings_source, "url", full_url)
    obs.obs_source_update(widget_source, settings_source)
    obs.obs_data_release(settings_source)
    obs.script_log(obs.LOG_INFO, "Базовый URL виджета обновлен (без параметров данных): " .. full_url)
  else
    obs.script_log(obs.LOG_ERROR, "Не удалось получить настройки источника для обновления базового URL.")
  end
end


function send_all_current_data_to_widget()
    local data_to_send = {
        wins = config.wins,
        losses = config.losses,
        rank = config.rank,
        bgType = config.bg_type,
        bgColor = config.bg_color,
        bgImage = config.bg_image,
        font = config.font,
        fontSize = config.font_size,
        winsColor = config.wins_color,
        lossesColor = config.losses_color,
        rankTextColor = config.rank_text_color,
        animDirection = config.anim_direction,
        animDurationIn = config.anim_duration_in,
        animStayTime = config.anim_stay_time,
        animDurationOut = config.anim_duration_out,
        hiddenTime = config.hidden_time
    }

    if not widget_source then
        obs.script_log(obs.LOG_WARNING, "Не могу отправить данные: источник 'Widget Stats' не найден.")
        return
    end

    if obs.obs_frontend_trigger_custom_event then
        local event_data = obs.obs_data_create()
        obs.obs_data_set_string(event_data, "commandType", "custom_event") 
        obs.obs_data_set_string(event_data, "commandData", json.encode({
            type = "update_all", 
            value = data_to_send
        }))
        obs.obs_frontend_trigger_custom_event("browser_source_custom_event", event_data)
        obs.obs_data_release(event_data)
        obs.script_log(obs.LOG_INFO, "Все данные отправлены через Custom Event: " .. json.encode(data_to_send))
    else
        obs.script_log(obs.LOG_INFO, "obs.obs_frontend_trigger_custom_event недоступен. Передача всех данных через URL-параметры.")

        local base_url_no_params = config.widget_url
        base_url_no_params = string.match(base_url_no_params, "^(.-%?)") or base_url_no_params
        base_url_no_params = string.gsub(base_url_no_params, "%?$", "")

        local url_params_str = ""
        local initial_param = true
        for k, v in pairs(data_to_send) do
            if not initial_param then
                url_params_str = url_params_str .. "&"
            end
            url_params_str = url_params_str .. k .. "=" .. url_encode(tostring(v))
            initial_param = false
        end

        local new_url = base_url_no_params .. "?_t=" .. os.time() .. "&" .. url_params_str

        local source_settings = obs.obs_source_get_settings(widget_source)
        if source_settings then
            obs.obs_data_set_string(source_settings, "url", new_url)
            obs.obs_source_update(widget_source, source_settings)
            obs.obs_data_release(source_settings)
            obs.script_log(obs.LOG_INFO, "URL виджета обновлен со всеми параметрами: " .. new_url)
        else
            obs.script_log(obs.LOG_ERROR, "Не удалось получить настройки источника для обновления URL со всеми параметрами.")
        end
    end
end

function send_data_to_widget(event_type, event_value)
  if event_type == "update_wins" then
      config.wins = tonumber(event_value) or 0
  elseif event_type == "update_losses" then
      config.losses = tonumber(event_value) or 0
  elseif event_type == "update_rank" then
      config.rank = tonumber(event_value.new_rank) or 0
  elseif event_type == "reset_stats" then
      config.wins = 0
      config.losses = 0
  end

  if not widget_source then
      obs.script_log(obs.LOG_WARNING, "Не могу отправить данные: источник 'Widget Stats' не найден.")
      return
  end

  if obs.obs_frontend_trigger_custom_event then
      local event_data = obs.obs_data_create()
      obs.obs_data_set_string(event_data, "commandType", "custom_event") -- Для JS
      local msg = {type = event_type}
      
      if event_type == "update_rank" then        
          msg.value = {
              rank = tonumber(event_value.new_rank) or 0,
              old_rank = tonumber(event_value.old_rank) or 0
          }
      elseif event_type == "reset_stats" then
          msg.value = {wins = 0, losses = 0, rank = 0}
      else
          msg.value = { [string.match(event_type, "update_(.*)")] = tonumber(event_value) or 0 }
      end
      obs.obs_data_set_string(event_data, "commandData", json.encode(msg))
      obs.obs_frontend_trigger_custom_event("browser_source_custom_event", event_data)
      obs.obs_data_release(event_data)
      obs.script_log(obs.LOG_INFO, "Данные отправлены через Custom Event: " .. json.encode(msg))
  else
      obs.script_log(obs.LOG_INFO, "Custom Event недоступен, вызываю полное обновление виджета через URL.")
      if type(config.rank) ~= "number" then
          config.rank = 0
          obs.script_log(obs.LOG_WARNING, "config.rank было не числом перед полным обновлением URL, сбрасываю на 0.")
      end
      send_all_current_data_to_widget()
  end
end

function increase_wins(pressed)
  if pressed then
    config.wins = config.wins + 1;
    send_data_to_widget("update_wins", config.wins)
  end
end

function increase_losses(pressed)
  if pressed then
    config.losses = config.losses + 1;
    send_data_to_widget("update_losses", config.losses)
  end
end

function increase_rank(pressed)
  if pressed then
    config.rank = tonumber(config.rank) or 0
    local old_rank = config.rank 
    config.rank = math.min(config.rank + 1, #ranks - 1)
    send_data_to_widget("update_rank", { new_rank = config.rank, old_rank = old_rank })
  end
end

function decrease_rank(pressed)
  if pressed then
    config.rank = tonumber(config.rank) or 0
    local old_rank = config.rank 
    config.rank = math.max(config.rank - 1, 0)
    send_data_to_widget("update_rank", { new_rank = config.rank, old_rank = old_rank })
  end
end

function reset_stats(pressed)
  if pressed then
    config.wins = 0;
    config.losses = 0;
    send_data_to_widget("reset_stats", nil) 
  end
end


function on_frontend_event(event)

    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED or
       event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED or
       event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
        
        obs.script_log(obs.LOG_INFO, "OBS Frontend event triggered, attempting to find/create widget source.")
        
        if not widget_source then
            widget_source = find_widget_source()
            if not widget_source and config.auto_create_source then
                widget_source = create_widget_source()
            end

            if widget_source then
                obs.script_log(obs.LOG_INFO, "Widget source found/created during frontend event. Sending initial data.")
                update_widget_source_base_url() 
                send_all_current_data_to_widget()
            else
                obs.script_log(obs.LOG_WARNING, "Widget source still not found/created after frontend event. Возможно, потребуется ручное создание.")
            end
        else
            obs.script_log(obs.LOG_INFO, "Widget source already exists. Re-sending current data due to frontend event.")
            send_all_current_data_to_widget() 
        end
    end
end


function script_properties()
  local props = obs.obs_properties_create()
  obs.obs_properties_add_bool(props, "auto_create_source", "Создавать источник 'Widget Stats' автоматически")
  obs.obs_properties_add_path(props, "widget_url", "Путь к widget.html", obs.OBS_PATH_FILE, "HTML Files (*.html)", nil)
  obs.obs_properties_add_int(props, "wins", "Победы", 0, 9999, 1)
  obs.obs_properties_add_int(props, "losses", "Поражения", 0, 9999, 1)
  local rank_prop = obs.obs_properties_add_list(props, "rank", "Ранг", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
  for _, r in ipairs(ranks) do obs.obs_property_list_add_int(rank_prop, r.name, r.value) end
  local bg_type_prop = obs.obs_properties_add_list(props, "bg_type", "Тип фона", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  obs.obs_property_list_add_string(bg_type_prop, "Цвет", "color")
  obs.obs_property_list_add_string(bg_type_prop, "Изображение", "image")
  obs.obs_properties_add_color(props, "bg_color", "Цвет фона")
  obs.obs_properties_add_int_slider(props, "bg_alpha", "Прозрачность фона (%)", 0, 100, 1)
  obs.obs_properties_add_path(props, "bg_image", "Изображение фона", obs.OBS_PATH_FILE, "Изображения (*.png *.jpg *.jpeg *.gif)", nil)
  obs.obs_properties_add_font(props, "font", "Шрифт и размер")
  obs.obs_properties_add_color(props, "wins_color", "Цвет побед")
  obs.obs_properties_add_color(props, "losses_color", "Цвет поражений")
  obs.obs_properties_add_color(props, "rank_text_color", "Цвет текста ранга")
  local anim_dir = obs.obs_properties_add_list(props, "anim_direction", "Направление анимации", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  obs.obs_property_list_add_string(anim_dir, "Сверху", "top")
  obs.obs_property_list_add_string(anim_dir, "Слева", "left")
  obs.obs_property_list_add_string(anim_dir, "Справа", "right")
  obs.obs_property_list_add_string(anim_dir, "Снизу", "bottom")
  obs.obs_properties_add_int(props, "anim_duration_in", "Длительность появления (мс)", 0, 5000, 50)
  obs.obs_properties_add_int(props, "anim_stay_time", "Время показа (мс)", 0, 60000, 500)
  obs.obs_properties_add_int(props, "anim_duration_out", "Длительность исчезновения (мс)", 0, 5000, 50)
  obs.obs_properties_add_int(props, "hidden_time", "Время в скрытом состоянии (мс)", 0, 60000, 1000)
  obs.obs_properties_add_button(props, "refresh_widget", "Обновить виджет (перезагрузить HTML)", function() update_widget_source_base_url(); return true end)
  obs.obs_properties_add_button(props, "reset_local_storage", "Сбросить кеш виджета в браузере (требует перезагрузки HTML)", function() shouldResetLocalStorage = true; update_widget_source_base_url(); return true end)

  obs.obs_properties_add_button(props, "find_create_source", "Найти/Создать источник 'Widget Stats' (вручную)", function()
      obs.script_log(obs.LOG_INFO, "Manual 'Find/Create Source' button pressed.")
      if not widget_source then
          widget_source = find_widget_source()
          if not widget_source and config.auto_create_source then
              widget_source = create_widget_source()
          end
      end

      if widget_source then
          obs.script_log(obs.LOG_INFO, "Widget source found/created manually. Updating URL and sending initial data.")
          update_widget_source_base_url()
          send_all_current_data_to_widget()
      else
          obs.script_log(obs.LOG_WARNING, "Failed to find/create widget source manually. Check logs and ensure OBS is ready.")
      end
      return true
  end)
  return props
end


function script_update(settings)
  local old_widget_url = config.widget_url
  
  config.auto_create_source = obs.obs_data_get_bool(settings, "auto_create_source")
  local path = obs.obs_data_get_string(settings, "widget_url")
  if path and path ~= "" then
    if not string.match(path, "^file:///") and not string.match(path, "^http://") and not string.match(path, "^https://") then
      path = string.gsub(path, "\\", "/")
      if string.match(path, "^%a:/") then
        path = "/" .. path
      end
      config.widget_url = "file:///" .. path
    else
      config.widget_url = path
    end
  else
    config.widget_url = "about:blank"
  end
  

  local current_wins = obs.obs_data_get_int(settings, "wins")
  local current_losses = obs.obs_data_get_int(settings, "losses")
  local current_rank = obs.obs_data_get_int(settings, "rank")
  local stats_changed = false
  if current_wins ~= config.wins then
    config.wins = current_wins
    stats_changed = true
  end
  if current_losses ~= config.losses then
    config.losses = current_losses
    stats_changed = true
  end
  if current_rank ~= config.rank then  
    local old_rank_for_js = config.rank
    config.rank = current_rank
    send_data_to_widget("update_rank", {new_rank = config.rank, old_rank = old_rank_for_js})
    stats_changed = false 
  end
  
  local new_bg_type = obs.obs_data_get_string(settings, "bg_type")
  local bg_color_int = obs.obs_data_get_int(settings, "bg_color")
  local alpha_percent = obs.obs_data_get_int(settings, "bg_alpha")
  local new_bg_color = obs.obs_data_get_string(settings, "bg_color")
  local new_bg_image = obs.obs_data_get_string(settings, "bg_image")
  local font_obj = obs.obs_data_get_obj(settings, "font")
  local new_font_face = ""
  local new_font_size = 0
  if font_obj then
    new_font_face = obs.obs_data_get_string(font_obj, "face")
    new_font_size = obs.obs_data_get_int(font_obj, "size")
    obs.obs_data_release(font_obj)
  end
  local new_wins_color = int_to_css_color(obs.obs_data_get_int(settings, "wins_color"))
  local new_losses_color = int_to_css_color(obs.obs_data_get_int(settings, "losses_color"))
  local new_rank_text_color = int_to_css_color(obs.obs_data_get_int(settings, "rank_text_color"))
  local new_anim_direction = obs.obs_data_get_string(settings, "anim_direction")
  local new_anim_duration_in = obs.obs_data_get_int(settings, "anim_duration_in")
  local new_anim_stay_time = obs.obs_data_get_int(settings, "anim_stay_time")
  local new_anim_duration_out = obs.obs_data_get_int(settings, "anim_duration_out")
  local new_hidden_time = obs.obs_data_get_int(settings, "hidden_time")


  local appearance_changed = false
  if new_bg_type ~= config.bg_type or new_bg_color ~= config.bg_color or new_bg_image ~= config.bg_image or
     new_font_face ~= config.font or new_font_size ~= config.font_size or
     new_wins_color ~= config.wins_color or new_losses_color ~= config.losses_color or new_rank_text_color ~= config.rank_text_color or
     new_anim_direction ~= config.anim_direction or new_anim_duration_in ~= config.anim_duration_in or
     new_anim_stay_time ~= config.anim_stay_time or new_anim_duration_out ~= config.anim_duration_out or new_hidden_time ~= config.hidden_time then
       
    appearance_changed = true
  end


  config.bg_type = new_bg_type
  config.bg_color = new_bg_color
  config.bg_image = new_bg_image
  config.font = new_font_face
  config.font_size = new_font_size
  config.wins_color = new_wins_color
  config.losses_color = new_losses_color
  config.rank_text_color = new_rank_text_color
  config.anim_direction = new_anim_direction
  config.anim_duration_in = new_anim_duration_in
  config.anim_stay_time = new_anim_stay_time
  config.anim_duration_out = new_anim_duration_out
  config.hidden_time = new_hidden_time


  if appearance_changed or stats_changed then
    send_all_current_data_to_widget()
  end


  if old_widget_url ~= config.widget_url then
    update_widget_source_base_url()
  end
end

function script_defaults(settings)
  obs.obs_data_set_default_bool(settings, "auto_create_source", true)
  obs.obs_data_set_default_int(settings, "wins", 0)
  obs.obs_data_set_default_int(settings, "losses", 0)
  obs.obs_data_set_default_int(settings, "rank", 0)
  obs.obs_data_set_default_string(settings, "bg_type", "color")
  obs.obs_data_set_default_int(settings, "bg_color", 0xFF000000) 
  obs.obs_data_set_default_int(settings, "bg_alpha", 70)
  local font_defaults = obs.obs_data_create()
  obs.obs_data_set_default_string(font_defaults, "face", "Arial")
  obs.obs_data_set_default_int(font_defaults, "size", 16)
  obs.obs_data_set_default_obj(settings, "font", font_defaults)
  obs.obs_data_release(font_defaults)
  obs.obs_data_set_default_int(settings, "wins_color", 0xFF00FF00) -- Green
  obs.obs_data_set_default_int(settings, "losses_color", 0xFFFF0000) -- Red
  obs.obs_data_set_default_int(settings, "rank_text_color", 0xFFFFFFFF) -- White
  obs.obs_data_set_default_string(settings, "anim_direction", "left")
  obs.obs_data_set_default_int(settings, "anim_duration_in", 500)
  obs.obs_data_set_default_int(settings, "anim_stay_time", 10000)
  obs.obs_data_set_default_int(settings, "anim_duration_out", 500)
  obs.obs_data_set_default_int(settings, "hidden_time", 8000)
end

function script_load(settings)
  obs.script_log(obs.LOG_INFO, "Скрипт виджета статистики загружен.")
  
  -- Восстанавливаем config из settings при загрузке скрипта
  config.auto_create_source = obs.obs_data_get_bool(settings, "auto_create_source")
  local path = obs.obs_data_get_string(settings, "widget_url")
  if path and path ~= "" then
    if not string.match(path, "^file:///") and not string.match(path, "^http://") and not string.match(path, "^https://") then
      path = string.gsub(path, "\\", "/")
      if string.match(path, "^%a:/") then
        path = "/" .. path
      end
      config.widget_url = "file:///" .. path
    else
      config.widget_url = path
    end
  else
    config.widget_url = "about:blank"
  end

  config.wins = obs.obs_data_get_int(settings, "wins")
  config.losses = obs.obs_data_get_int(settings, "losses")
  local loaded_rank = obs.obs_data_get_int(settings, "rank")
  if type(loaded_rank) == "number" then
    config.rank = loaded_rank
  else
    config.rank = 0 
    obs.script_log(obs.LOG_WARNING, "Loaded rank was not a number, resetting to 0.")
  end
  

  local bg_color_int_loaded = obs.obs_data_get_int(settings, "bg_color")
  local alpha_percent_loaded = obs.obs_data_get_int(settings, "bg_alpha")
  config.bg_color = int_to_css_color(bit.bor(bit.lshift(math.floor(alpha_percent_loaded/100 * 255), 24), bg_color_int_loaded))

  config.bg_image = obs.obs_data_get_string(settings, "bg_image")
  local font_obj = obs.obs_data_get_obj(settings, "font")
  if font_obj then
    config.font = obs.obs_data_get_string(font_obj, "face")
    config.font_size = obs.obs_data_get_int(font_obj, "size")
    obs.obs_data_release(font_obj)
  end
  config.wins_color = int_to_css_color(obs.obs_data_get_int(settings, "wins_color"))
  config.losses_color = int_to_css_color(obs.obs_data_get_int(settings, "losses_color"))
  config.rank_text_color = int_to_css_color(obs.obs_data_get_int(settings, "rank_text_color"))
  config.anim_direction = obs.obs_data_get_string(settings, "anim_direction")
  config.anim_duration_in = obs.obs_data_get_int(settings, "anim_duration_in")
  config.anim_stay_time = obs.obs_data_get_int(settings, "anim_stay_time")
  config.anim_duration_out = obs.obs_data_get_int(settings, "anim_duration_out")
  config.hidden_time = obs.obs_data_get_int(settings, "hidden_time")

  -- Регистрация горячих клавиш
  hotkey_increase_wins_id = obs.obs_hotkey_register_frontend("stat_widget_increase_wins", "Виджет: +1 Победа", increase_wins)
  local hk_array = obs.obs_data_get_array(settings, "stat_widget_increase_wins")
  if hk_array then
    obs.obs_hotkey_load(hotkey_increase_wins_id, hk_array)
    obs.obs_data_array_release(hk_array)
  end

  hotkey_increase_losses_id = obs.obs_hotkey_register_frontend("stat_widget_increase_losses", "Виджет: +1 Поражение", increase_losses)
  hk_array = obs.obs_data_get_array(settings, "stat_widget_increase_losses")
  if hk_array then
    obs.obs_hotkey_load(hotkey_increase_losses_id, hk_array)
    obs.obs_data_array_release(hk_array)
  end

  hotkey_increase_rank_id = obs.obs_hotkey_register_frontend("stat_widget_increase_rank", "Виджет: Повысить ранг", increase_rank)
  hk_array = obs.obs_data_get_array(settings, "stat_widget_increase_rank")
  if hk_array then
    obs.obs_hotkey_load(hotkey_increase_rank_id, hk_array)
    obs.obs_data_array_release(hk_array)
  end

  hotkey_decrease_rank_id = obs.obs_hotkey_register_frontend("stat_widget_decrease_rank", "Виджет: Понизить ранг", decrease_rank)
  hk_array = obs.obs_data_get_array(settings, "stat_widget_decrease_rank")
  if hk_array then
    obs.obs_hotkey_load(hotkey_decrease_rank_id, hk_array)
    obs.obs_data_array_release(hk_array)
  end

  hotkey_reset_stats_id = obs.obs_hotkey_register_frontend("stat_widget_reset_stats", "Виджет: Сбросить счет", reset_stats)
  hk_array = obs.obs_data_get_array(settings, "stat_widget_reset_stats")
  if hk_array then
    obs.obs_hotkey_load(hotkey_reset_stats_id, hk_array)
    obs.obs_data_array_release(hk_array)
  end


  frontend_event_callback_id = obs.obs_frontend_add_event_callback(on_frontend_event)


  widget_source = find_widget_source()
  if widget_source then
      obs.script_log(obs.LOG_INFO, "Widget source found on script load. Sending initial data.")
      update_widget_source_base_url()
      send_all_current_data_to_widget()
  else
      obs.script_log(obs.LOG_WARNING, "Widget source not found on script load. Will attempt creation/finding on next scene change/stream event.")
  end
end

function script_save(settings)
  obs.obs_data_set_bool(settings, "auto_create_source", config.auto_create_source)
  obs.obs_data_set_string(settings, "widget_url", config.widget_url)
  obs.obs_data_set_int(settings, "wins", config.wins)
  obs.obs_data_set_int(settings, "losses", config.losses)
  obs.obs_data_set_int(settings, "rank", config.rank)
  obs.obs_data_set_string(settings, "bg_type", config.bg_type)


  local bg_r, bg_g, bg_b, bg_a_float = string.match(config.bg_color, "rgba%((%d+),(%d+),(%d+),([%d%.]+)%)")
  if bg_r then -- Если это rgba строка
    bg_r = tonumber(bg_r) or 0
    bg_g = tonumber(bg_g) or 0
    bg_b = tonumber(bg_b) or 0
    local bg_a_percent = math.floor((tonumber(bg_a_float) or 0) * 100)
    local bg_color_for_obs_int = bit.bor(bit.lshift(bg_r, 16), bit.lshift(bg_g, 8), bg_b)
    obs.obs_data_set_int(settings, "bg_color", bg_color_for_obs_int)
    obs.obs_data_set_int(settings, "bg_alpha", bg_a_percent)
  else 
    local hex_color = string.match(config.bg_color, "#([%x%x%x%x%x%x])")
    if hex_color then
      local r_hex = string.sub(hex_color, 1, 2)
      local g_hex = string.sub(hex_color, 3, 4)
      local b_hex = string.sub(hex_color, 5, 6)   
      obs.obs_data_set_int(settings, "bg_color", obs_color_int)
      obs.obs_data_set_int(settings, "bg_alpha", 100) 
    end
  end
  
  obs.obs_data_set_string(settings, "bg_image", config.bg_image)

  local font_obj = obs.obs_data_create()
  obs.obs_data_set_string(font_obj, "face", config.font)
  obs.obs_data_set_int(font_obj, "size", config.font_size)
  obs.obs_data_set_obj(settings, "font", font_obj)
  obs.obs_data_release(font_obj)

  obs.obs_data_set_int(settings, "wins_color", css_color_to_int(config.wins_color))
  obs.obs_data_set_int(settings, "losses_color", css_color_to_int(config.losses_color))
  obs.obs_data_set_int(settings, "rank_text_color", css_color_to_int(config.rank_text_color))

  obs.obs_data_set_string(settings, "anim_direction", config.anim_direction)
  obs.obs_data_set_int(settings, "anim_duration_in", config.anim_duration_in)
  obs.obs_data_set_int(settings, "anim_stay_time", config.anim_stay_time)
  obs.obs_data_set_int(settings, "anim_duration_out", config.anim_duration_out)
  obs.obs_data_set_int(settings, "hidden_time", config.hidden_time)

  -- Сохранение горячих клавиш
  local hk_array = obs.obs_hotkey_save(hotkey_increase_wins_id)
  if hk_array then
    obs.obs_data_set_array(settings, "stat_widget_increase_wins", hk_array)
    obs.obs_data_array_release(hk_array)
  end
  
  hk_array = obs.obs_hotkey_save(hotkey_increase_losses_id)
  if hk_array then
    obs.obs_data_set_array(settings, "stat_widget_increase_losses", hk_array)
    obs.obs_data_array_release(hk_array)
  end
  
  hk_array = obs.obs_hotkey_save(hotkey_increase_rank_id)
  if hk_array then
    obs.obs_data_set_array(settings, "stat_widget_increase_rank", hk_array)
    obs.obs_data_array_release(hk_array)
  end
  
  hk_array = obs.obs_hotkey_save(hotkey_decrease_rank_id)
  if hk_array then
    obs.obs_data_set_array(settings, "stat_widget_decrease_rank", hk_array)
    obs.obs_data_array_release(hk_array)
  end
  
  hk_array = obs.obs_hotkey_save(hotkey_reset_stats_id)
  if hk_array then
    obs.obs_data_set_array(settings, "stat_widget_reset_stats", hk_array)
    obs.obs_data_array_release(hk_array)
  end
end

function script_unload()
  -- Отмена регистрации горячих клавиш при выгрузке скрипта
  if hotkey_increase_wins_id ~= obs.OBS_INVALID_HOTKEY_ID then obs.obs_hotkey_unregister(hotkey_increase_wins_id) end
  if hotkey_increase_losses_id ~= obs.OBS_INVALID_HOTKEY_ID then obs.obs_hotkey_unregister(hotkey_increase_losses_id) end
  if hotkey_increase_rank_id ~= obs.OBS_INVALID_HOTKEY_ID then obs.obs_hotkey_unregister(hotkey_increase_rank_id) end
  if hotkey_decrease_rank_id ~= obs.OBS_INVALID_HOTKEY_ID then obs.obs_hotkey_unregister(hotkey_decrease_rank_id) end
  if hotkey_reset_stats_id ~= obs.OBS_INVALID_HOTKEY_ID then obs.obs_hotkey_unregister(hotkey_reset_stats_id) end

  -- Отменяем регистрацию коллбэка событий
  if frontend_event_callback_id then
      obs.obs_frontend_remove_event_callback(frontend_event_callback_id)
      frontend_event_callback_id = nil
  end

  -- Освобождаем глобальную ссылку на источник при выгрузке скрипта
  if widget_source then
    obs.obs_source_release(widget_source)
    widget_source = nil
  end
  obs.script_log(obs.LOG_INFO, "Скрипт виджета статистики выгружен.")
end