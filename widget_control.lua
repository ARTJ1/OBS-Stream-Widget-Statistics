obs = obslua
local bit = require("bit")

-- Основные параметры виджета
local widget_url = "file:///C:/path/to/widget.html"  -- Укажите актуальный путь к widget.html
local wins = 0
local losses = 0
local rank = 0  -- Например, 0 соответствует "Bronze 5" в вашем JS

local ranks = {}
-- Основные ранги (Bronze - Champion)
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

local settings = {
    widget_url = "file:///C:/path/to/widget.html",
    wins = 0,
    losses = 0,
    rank = 0,
    bg_type = "color",
    bg_color = "rgba(0,0,0,0.7)",
    bg_image = "",
    font = "Arial, sans-serif",
    font_size = 16,
    wins_color = "#00ff00",
    losses_color = "#ff0000",
    rank_text_color = "#ffffff",
    anim_direction = "left",
    anim_duration_in = 1000,
    anim_stay_time = 10000,
    anim_duration_out = 1000,
    hidden_time = 10000,
    bg_alpha = 70,
    auto_create_source = true
}

local widget_source = nil
local settings_global = nil


---------------------------------------------------
-- Функция для URL‑кодирования строки
---------------------------------------------------
function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

---------------------------------------------------
-- Преобразование цвета в CSS-строку
---------------------------------------------------
function int_to_css_color(color_int)
    local a = bit.rshift(bit.band(color_int, 0xFF000000), 24)
    local b = bit.rshift(bit.band(color_int, 0x00FF0000), 16)
    local g = bit.rshift(bit.band(color_int, 0x0000FF00), 8)
    local r = bit.band(color_int, 0x000000FF)
    if a < 255 then
        return string.format("rgba(%d, %d, %d, %.2f)", r, g, b, a / 255)
    else
        return string.format("#%02x%02x%02x", r, g, b)
    end
end

---------------------------------------------------
-- Обновление браузерного источника (передача параметров через URL)
---------------------------------------------------
function update_widget_source()
    if not widget_source  then
        local sources = find_widget_sources()
        if #sources > 0 then
            widget_source = sources[1]
        else
            if settings.auto_create_source then
                create_widget_source()
                if not widget_source then return end
            else
                return
            end
        end
    end

    local params = {
        wins = settings.wins,
        losses = settings.losses,
        rank = settings.rank,
        bgType = settings.bg_type,  -- camelCase
        bgColor = urlencode(settings.bg_color),
        bgImage = urlencode(settings.bg_image),
        font = urlencode(settings.font),
        fontSize = settings.font_size,
        winsColor = urlencode(settings.wins_color),  -- camelCase
        lossesColor = urlencode(settings.losses_color),  -- camelCase
        rankTextColor = urlencode(settings.rank_text_color),  -- camelCase
        animDirection = settings.anim_direction,  -- camelCase
        animDurationIn = settings.anim_duration_in,
        animStayTime = settings.anim_stay_time,
        animDurationOut = settings.anim_duration_out,
        hiddenTime = settings.hidden_time
    }

    -- Формируем URL-строку
    local query = ""
    for k, v in pairs(params) do
        query = query .. k .. "=" .. tostring(v) .. "&"
    end
    local full_url = settings.widget_url .. "?" .. query .. "_t="..os.time()

    -- Обновляем источник
    local source_settings = obs.obs_data_create()
    obs.obs_data_set_string(source_settings, "url", full_url)
    obs.obs_source_update(widget_source, source_settings)
    obs.obs_data_release(source_settings)
end

---------------------------------------------------
-- Поиск источника "Widget Stats" в текущей сцене
---------------------------------------------------
function find_widget_sources()
    local sources = obs.obs_enum_sources()
    local result = {}
    
    for _, src in ipairs(sources) do
        if obs.obs_source_get_name(src) == "Widget Stats" then
            table.insert(result, obs.obs_source_get_ref(src))
        end
    end
    
    obs.source_list_release(sources)
    return result
end

---------------------------------------------------
-- Создание источника виджета
---------------------------------------------------
function create_widget_source()
    local current_scene = obs.obs_frontend_get_current_scene()
    if not current_scene then return end

    local scene = obs.obs_scene_from_source(current_scene)
    local settings = obs.obs_data_create()
    
    obs.obs_data_set_string(settings, "url", widget_url)
    obs.obs_data_set_int(settings, "width", 470)
    obs.obs_data_set_int(settings, "height", 100)
    
    widget_source = obs.obs_source_create("browser_source", "Widget Stats", settings, nil)
    obs.obs_scene_add(scene, widget_source)
    
    -- Корректное освобождение ресурсов --
    obs.obs_data_release(settings)
    obs.obs_scene_release(scene)
    obs.obs_source_release(current_scene)
end

---------------------------------------------------
-- Горячие клавиши
---------------------------------------------------
local hotkey_increase_wins_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_increase_losses_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_increase_rank_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_decrease_rank_id = obs.OBS_INVALID_HOTKEY_ID
local hotkey_reset_stats_id = obs.OBS_INVALID_HOTKEY_ID

function increase_wins(pressed)
    if not pressed then return end
    settings.wins = settings.wins + 1 
    update_widget_source()
end

function increase_losses(pressed)
    if not pressed then return end
    settings.losses = settings.losses + 1
    update_widget_source()
end

function increase_rank(pressed)
    if not pressed then return end
    settings.rank = settings.rank + 1
    update_widget_source()
end

function decrease_rank(pressed)
    if not pressed then return end
    if settings.rank > 0 then settings.rank = settings.rank - 1 end
    update_widget_source()
end

function reset_stats(pressed)
    if not pressed then return end
    settings.wins = 0  
    settings.losses = 0
    update_widget_source()
end

---------------------------------------------------
-- Настройки скрипта OBS (панель свойств)
---------------------------------------------------
function script_description()
    return "Интегрированный виджет статистики с настройками внешнего вида и анимации.\n" ..
           "Настройте цвета, шрифт и анимацию. Если автоматическое создание отключено, создайте источник вручную с именем 'Widget Stats'."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_bool(props, "auto_create_source", "Создавать источник виджета при запуске")
    obs.obs_properties_add_text(props, "widget_url", "URL виджета", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(props, "wins", "Победы (начальное значение)", 0, 1000, 1)
    obs.obs_properties_add_int(props, "losses", "Поражения (начальное значение)", 0, 1000, 1)
    local rank_prop = obs.obs_properties_add_list(props, "rank", "Ранг", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    for _, r in ipairs(ranks) do
        obs.obs_property_list_add_int(rank_prop, r.name, r.value)
    end
    local bg_type_prop = obs.obs_properties_add_list(props, "bg_type", "Тип фона", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(bg_type_prop, "color", "color")
    obs.obs_property_list_add_string(bg_type_prop, "image", "image")
    obs.obs_properties_add_color(props, "bg_color", "Цвет фона")
    obs.obs_properties_add_int(props, "bg_alpha", "Прозрачность фона (%)", 0, 100, 1)
    obs.obs_properties_add_path(props, "bg_image", "Путь к изображению для фона", obs.OBS_PATH_FILE, "", nil)
    obs.obs_properties_add_font(props, "font", "Выберите шрифт")
    obs.obs_properties_add_color(props, "wins_color", "Цвет текста побед")
    obs.obs_properties_add_color(props, "losses_color", "Цвет текста поражений")
    obs.obs_properties_add_color(props, "rank_text_color", "Цвет текста ранга")
    local anim_dir = obs.obs_properties_add_list(props, "anim_direction", "Направление анимации", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(anim_dir, "left", "left")
    obs.obs_property_list_add_string(anim_dir, "right", "right")
    obs.obs_property_list_add_string(anim_dir, "top", "top")
    obs.obs_property_list_add_string(anim_dir, "bottom", "bottom")
    obs.obs_properties_add_int(props, "anim_duration_in", "Длительность появления (ms)", 100, 10000, 10)
    obs.obs_properties_add_int(props, "anim_stay_time", "Время показа (ms)", 100, 60000, 10)
    obs.obs_properties_add_int(props, "anim_duration_out", "Длительность исчезновения (ms)", 100, 10000, 10)
    obs.obs_properties_add_int(props, "hidden_time", "Время скрытия (ms)", 0, 60000, 10)
    -- Кнопка для безопасного удаления виджета и остановки скрипта
   -- obs.obs_properties_add_button(props, "stop_button", "Остановить скрипт и удалить виджет", stop_script_and_delete_widget)
    return props
end

function script_update(script_settings)
 -- Обновляем все параметры из GUI
 settings.auto_create_source = obs.obs_data_get_bool(script_settings, "auto_create_source")
 settings.widget_url = obs.obs_data_get_string(script_settings, "widget_url")
 settings.wins = obs.obs_data_get_int(script_settings, "wins")
 settings.losses = obs.obs_data_get_int(script_settings, "losses")
 settings.rank = obs.obs_data_get_int(script_settings, "rank")
 settings.bg_type = obs.obs_data_get_string(script_settings, "bg_type")
 
 -- Обработка цвета фона с прозрачностью
 local bg_color_int = obs.obs_data_get_int(script_settings, "bg_color")
 local alpha = math.floor((obs.obs_data_get_int(script_settings, "bg_alpha") or 70) * 255 / 100)
 settings.bg_color = string.format("rgba(%d,%d,%d,%.2f)",
     bit.band(bg_color_int, 0xFF),
     bit.band(bit.rshift(bg_color_int, 8), 0xFF),
     bit.band(bit.rshift(bg_color_int, 16), 0xFF),
     alpha / 255
 )
 
 settings.bg_image = obs.obs_data_get_string(script_settings, "bg_image")
 
 -- Обработка шрифта
 local font_obj = obs.obs_data_get_obj(script_settings, "font")
 settings.font = obs.obs_data_get_string(font_obj, "face") or "Arial, sans-serif"
 settings.font_size = obs.obs_data_get_int(font_obj, "size") or 16
 obs.obs_data_release(font_obj)
 
 -- Цвета текста
 settings.wins_color = int_to_css_color(obs.obs_data_get_int(script_settings, "wins_color"))
 settings.losses_color = int_to_css_color(obs.obs_data_get_int(script_settings, "losses_color"))
 settings.rank_text_color = int_to_css_color(obs.obs_data_get_int(script_settings, "rank_text_color"))
 
 -- Настройки анимации
 settings.anim_direction = obs.obs_data_get_string(script_settings, "anim_direction")
 settings.anim_duration_in = obs.obs_data_get_int(script_settings, "anim_duration_in")
 settings.anim_stay_time = obs.obs_data_get_int(script_settings, "anim_stay_time")
 settings.anim_duration_out = obs.obs_data_get_int(script_settings, "anim_duration_out")
 settings.hidden_time = obs.obs_data_get_int(script_settings, "hidden_time")
 
 update_widget_source()
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "auto_create_source", true)
    obs.obs_data_set_default_string(settings, "widget_url", "file:///C:/path/to/widget.html")
    obs.obs_data_set_default_int(settings, "wins", 0)
    obs.obs_data_set_default_int(settings, "losses", 0)
    obs.obs_data_set_default_int(settings, "rank", 0)
    obs.obs_data_set_default_string(settings, "bg_type", "color")
    obs.obs_data_set_default_int(settings, "bg_color", 0xB2000000)
    obs.obs_data_set_default_int(settings, "bg_alpha", 70)
    obs.obs_data_set_default_string(settings, "bg_image", "")
    
    -- Создаем отдельный объект для шрифта
    local font_defaults = obs.obs_data_create()
    obs.obs_data_set_default_string(font_defaults, "face", "Arial, sans-serif")
    obs.obs_data_set_default_int(font_defaults, "size", 16)
    obs.obs_data_set_default_obj(settings, "font", font_defaults)
    obs.obs_data_release(font_defaults)
    
    obs.obs_data_set_default_int(settings, "wins_color", 0xFF00FF00)
    obs.obs_data_set_default_int(settings, "losses_color", 0xFF0000FF)
    obs.obs_data_set_default_int(settings, "rank_text_color", 0xFFFFFFFF)
    obs.obs_data_set_default_string(settings, "anim_direction", "left")
    obs.obs_data_set_default_int(settings, "anim_duration_in", 1000)
    obs.obs_data_set_default_int(settings, "anim_stay_time", 10000)
    obs.obs_data_set_default_int(settings, "anim_duration_out", 1000)
    obs.obs_data_set_default_int(settings, "hidden_time", 10000)
end

function delayed_init()
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        obs.script_log(obs.LOG_WARNING, "Delayed init: текущая сцена недоступна.")
        return
    end
    obs.timer_remove(delayed_init)
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.script_log(obs.LOG_WARNING, "Delayed init: не удалось получить сцену из источника!")
        obs.obs_source_release(scene_source)
        return
    end
    obs.obs_source_release(scene_source)
    local widget_sources = find_widget_sources()
    if #widget_sources > 0 then
        widget_source = widget_sources[1]
        update_widget_source()
        -- Освобождаем лишние ссылки, если они есть
        for i = 2, #widget_sources do
            obs.obs_source_release(widget_sources[i])
        end
    else
        obs.script_log(obs.LOG_INFO, "Виджет 'Widget Stats' не найден.")
        if auto_create_source then
            obs.script_log(obs.LOG_INFO, "Delayed init: источник виджета не найден, создаем новый.")
            create_widget_source()
        else
            obs.script_log(obs.LOG_INFO, "Delayed init: автоматическое создание отключено.")
        end
    end    
end

function script_load(settings)
    settings_global = settings
    -- Проверяем значение шрифта; если не задан – устанавливаем значение по умолчанию
    local font_obj = obs.obs_data_get_obj(settings, "font")
    local face = obs.obs_data_get_string(font_obj, "face")
    obs.obs_data_release(font_obj)
    if not face or face == "" then
        local def = obs.obs_data_create()
        obs.obs_data_set_string(def, "face", "Arial, sans-serif")
        obs.obs_data_set_obj(settings, "font", def)
        obs.obs_data_release(def)
        obs.script_log(obs.LOG_INFO, "Не выбран шрифт, устанавливаем Arial, sans-serif по умолчанию.")
    else
        obs.script_log(obs.LOG_INFO, "Выбранный шрифт: " .. face)
    end

   


    obs.script_log(obs.LOG_INFO, "Скрипт загружается...")
    local widget_sources = find_widget_sources()
    if #widget_sources > 0 then
        for _, src in ipairs(widget_sources) do
            obs.script_log(obs.LOG_INFO, "Найден виджет: " .. obs.obs_source_get_name(src))
            -- Когда источник больше не нужен, не забудьте освободить его:
            obs.obs_source_release(src)
        end
    else
        obs.script_log(obs.LOG_INFO, "Виджет 'Widget Stats' не найден.")
        obs.timer_add(delayed_init, 500)
    end
   
    obs.script_log(obs.LOG_INFO, "Регистрация горячих клавиш...")
    hotkey(settings)
end

function hotkey(settings)
    obs.script_log(obs.LOG_INFO, "Выполняется функция hotkey()...")
    hotkey_increase_wins_id = obs.obs_hotkey_register_frontend("widget_increase_wins", "Увеличить победы", increase_wins)
    local hk_array = obs.obs_data_get_array(settings, "widget_increase_wins")
    obs.obs_hotkey_load(hotkey_increase_wins_id, hk_array)
    obs.obs_data_array_release(hk_array)

    hotkey_increase_losses_id = obs.obs_hotkey_register_frontend("widget_increase_losses", "Увеличить поражения", increase_losses)
    hk_array = obs.obs_data_get_array(settings, "widget_increase_losses")
    obs.obs_hotkey_load(hotkey_increase_losses_id, hk_array)
    obs.obs_data_array_release(hk_array)

    hotkey_increase_rank_id = obs.obs_hotkey_register_frontend("widget_increase_rank", "Повысить ранг", increase_rank)
    hk_array = obs.obs_data_get_array(settings, "widget_increase_rank")
    obs.obs_hotkey_load(hotkey_increase_rank_id, hk_array)
    obs.obs_data_array_release(hk_array)

    hotkey_decrease_rank_id = obs.obs_hotkey_register_frontend("widget_decrease_rank", "Понизить ранг", decrease_rank)
    hk_array = obs.obs_data_get_array(settings, "widget_decrease_rank")
    obs.obs_hotkey_load(hotkey_decrease_rank_id, hk_array)
    obs.obs_data_array_release(hk_array)

    hotkey_reset_stats_id = obs.obs_hotkey_register_frontend("widget_reset_stats", "Сброс статистики", reset_stats)
    hk_array = obs.obs_data_get_array(settings, "widget_reset_stats")
    obs.obs_hotkey_load(hotkey_reset_stats_id, hk_array)
    obs.obs_data_array_release(hk_array)
end

function script_save(script_settings)
    -- Сохраняем статистику из таблицы settings
    obs.obs_data_set_int(script_settings, "wins", settings.wins)
    obs.obs_data_set_int(script_settings, "losses", settings.losses)
    obs.obs_data_set_int(script_settings, "rank", settings.rank)
    
    -- Сохраняем горячие клавиши
    local hk_array = obs.obs_hotkey_save(hotkey_increase_wins_id)
    obs.obs_data_set_array(script_settings, "widget_increase_wins", hk_array)
    obs.obs_data_array_release(hk_array)
    
    hk_array = obs.obs_hotkey_save(hotkey_increase_losses_id)
    obs.obs_data_set_array(script_settings, "widget_increase_losses", hk_array)
    obs.obs_data_array_release(hk_array)
    
    hk_array = obs.obs_hotkey_save(hotkey_increase_rank_id)
    obs.obs_data_set_array(script_settings, "widget_increase_rank", hk_array)
    obs.obs_data_array_release(hk_array)
    
    hk_array = obs.obs_hotkey_save(hotkey_decrease_rank_id)
    obs.obs_data_set_array(script_settings, "widget_decrease_rank", hk_array)
    obs.obs_data_array_release(hk_array)
    
    hk_array = obs.obs_hotkey_save(hotkey_reset_stats_id)
    obs.obs_data_set_array(script_settings, "widget_reset_stats", hk_array)
    obs.obs_data_array_release(hk_array)
end

---------------------------------------------------
-- Функция script_unload – вызывается OBS при выгрузке скрипта
---------------------------------------------------
function script_unload()
    if widget_source then
        obs.obs_source_release(widget_source)
        widget_source = nil
    end
end
---------------------------------------------------
-- Функция для остановки всех таймеров и горячих клавиш
---------------------------------------------------
function stop_all_activity()
    -- Удаляем таймер отложенной инициализации (если запущен)
    obs.timer_remove(delayed_init)

    -- Отменяем регистрацию горячих клавиш
    if hotkey_increase_wins_id and hotkey_increase_wins_id ~= obs.OBS_INVALID_HOTKEY_ID then
        obs.obs_hotkey_unregister(hotkey_increase_wins_id)
        hotkey_increase_wins_id = obs.OBS_INVALID_HOTKEY_ID
    end
    if hotkey_increase_losses_id and hotkey_increase_losses_id ~= obs.OBS_INVALID_HOTKEY_ID then
        obs.obs_hotkey_unregister(hotkey_increase_losses_id)
        hotkey_increase_losses_id = obs.OBS_INVALID_HOTKEY_ID
    end
    if hotkey_increase_rank_id and hotkey_increase_rank_id ~= obs.OBS_INVALID_HOTKEY_ID then
        obs.obs_hotkey_unregister(hotkey_increase_rank_id)
        hotkey_increase_rank_id = obs.OBS_INVALID_HOTKEY_ID
    end
    if hotkey_decrease_rank_id and hotkey_decrease_rank_id ~= obs.OBS_INVALID_HOTKEY_ID then
        obs.obs_hotkey_unregister(hotkey_decrease_rank_id)
        hotkey_decrease_rank_id = obs.OBS_INVALID_HOTKEY_ID
    end
    if hotkey_reset_stats_id and hotkey_reset_stats_id ~= obs.OBS_INVALID_HOTKEY_ID then
        obs.obs_hotkey_unregister(hotkey_reset_stats_id)
        hotkey_reset_stats_id = obs.OBS_INVALID_HOTKEY_ID
    end

    obs.script_log(obs.LOG_INFO, "stop_all_activity: Все таймеры и горячие клавиши остановлены.")
end


---------------------------------------------------
-- Функция для удаления источника виджета из сцены
---------------------------------------------------
function delete_widget_source()
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        obs.script_log(obs.LOG_WARNING, "delete_widget_source: текущая сцена недоступна!")
        return
    end

    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.script_log(obs.LOG_WARNING, "delete_widget_source: не удалось получить сцену из источника!")
        obs.obs_source_release(scene_source)
        return
    end

    -- Если в сцене есть источник с именем "Widget Stats", удаляем его
    local item = obs.obs_scene_find_source(scene, "Widget Stats")
    if item then
        obs.obs_sceneitem_remove(item)
        obs.script_log(obs.LOG_INFO, "delete_widget_source: Виджет удалён из сцены.")
    else
        obs.script_log(obs.LOG_INFO, "delete_widget_source: Виджет не найден в сцене.")
    end

    obs.obs_scene_release(scene)
    obs.obs_source_release(scene_source)
end

function stop_script_and_delete_widget()
    stop_all_activity()
    delete_widget_source()
   
    widget_source = nil
    if settings_global and obs.obs_data_valid(settings_global) then
        obs.obs_data_release(settings_global)
        settings_global = nil
    end
    collectgarbage("collect")
    obs.script_log(obs.LOG_INFO, "stop_script_and_delete_widget: Скрипт остановлен и виджет удалён безопасно.")
    return true
end

