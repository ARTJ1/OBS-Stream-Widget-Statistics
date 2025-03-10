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

-- Настройки внешнего вида
local bg_type = "color"          -- "color" или "image"
local bg_color = "rgba(0,0,0,0.7)"
local bg_image = ""
local font = "Arial, sans-serif" -- значение по умолчанию
local font_size_global = 0   
local wins_color = "#00ff00"
local losses_color = "#ff0000"
local rank_text_color = "#ffffff"

-- Настройки анимации (в мс)
local anim_direction = "left"
local anim_duration_in = 1000
local anim_stay_time = 10000
local anim_duration_out = 1000
local hidden_time = 10000

local auto_create_source = true
local bg_alpha = 70

local widget_source = nil
local settings_global = nil
local stopped = false

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
    if widget_source then
        local settings = obs.obs_data_create()
        local new_url = widget_url ..
            "?wins=" .. wins ..
            "&losses=" .. losses ..
            "&rank=" .. rank ..
            "&bgType=" .. urlencode(bg_type) ..
            "&bgColor=" .. urlencode(bg_color) ..
            "&bgImage=" .. urlencode(bg_image) ..
            "&font=" .. urlencode(font) ..
            "&fontSize=" .. tostring(font_size_global) .. 
            "&winsColor=" .. urlencode(wins_color) ..
            "&lossesColor=" .. urlencode(losses_color) ..
            "&rankTextColor=" .. urlencode(rank_text_color) ..
            "&animDirection=" .. urlencode(anim_direction) ..
            "&animDurationIn=" .. anim_duration_in ..
            "&animStayTime=" .. anim_stay_time ..
            "&animDurationOut=" .. anim_duration_out ..
            "&hiddenTime=" .. hidden_time ..
            "&_ts=" .. os.time()
        obs.obs_data_set_string(settings, "url", new_url)
        obs.obs_source_update(widget_source, settings)
        obs.obs_data_release(settings)
    end
end

---------------------------------------------------
-- Поиск источника "Widget Stats" в текущей сцене
---------------------------------------------------
function find_widget_source()
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then return nil end
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.obs_source_release(scene_source)
        return nil
    end
    local items = obs.obs_scene_enum_items(scene)
    local found = nil
    for i, item in ipairs(items) do
        local src = obs.obs_sceneitem_get_source(item)
        local src_name = obs.obs_source_get_name(src)
        if src_name == "Widget Stats" then
            found = obs.obs_source_get_ref(src)  -- увеличить счетчик ссылок
            break
        end
    end
    obs.sceneitem_list_release(items)
    obs.obs_source_release(scene_source)
    return found
end

---------------------------------------------------
-- Создание источника виджета
---------------------------------------------------
function create_widget_source()
    local scene_source = obs.obs_frontend_get_current_scene()
    if not scene_source then
        obs.script_log(obs.LOG_WARNING, "Не удалось получить текущую сцену!")
        return
    end
    local scene = obs.obs_scene_from_source(scene_source)
    if not scene then
        obs.script_log(obs.LOG_WARNING, "Не удалось получить сцену из источника!")
        obs.obs_source_release(scene_source)
        return
    end
    obs.script_log(obs.LOG_INFO, "Сцена успешно получена.")
    local source_settings = obs.obs_data_create()
    local initial_url = widget_url .. "?_ts=" .. os.time()
    obs.obs_data_set_string(source_settings, "url", initial_url)
    obs.obs_data_set_int(source_settings, "width", 320)
    obs.obs_data_set_int(source_settings, "height", 100)
    widget_source = obs.obs_source_create("browser_source", "Widget Stats", source_settings, nil)
    if not widget_source then
        obs.script_log(obs.LOG_WARNING, "Не удалось создать источник виджета!")
        obs.obs_data_release(source_settings)
        return
    end
    obs.obs_scene_add(scene, widget_source)
    obs.obs_data_release(source_settings)
    obs.obs_source_release(scene_source)
    obs.script_log(obs.LOG_INFO, "Источник виджета успешно добавлен в сцену.")
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
    wins = wins + 1
    update_widget_source()
end

function increase_losses(pressed)
    if not pressed then return end
    losses = losses + 1
    update_widget_source()
end

function increase_rank(pressed)
    if not pressed then return end
    rank = rank + 1
    update_widget_source()
end

function decrease_rank(pressed)
    if not pressed then return end
    if rank > 0 then rank = rank - 1 end
    update_widget_source()
end

function reset_stats(pressed)
    if not pressed then return end
    wins = 0
    losses = 0
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

function script_update(settings)
    auto_create_source = obs.obs_data_get_bool(settings, "auto_create_source")
    widget_url = obs.obs_data_get_string(settings, "widget_url")
    wins = obs.obs_data_get_int(settings, "wins")
    losses = obs.obs_data_get_int(settings, "losses")
    rank = obs.obs_data_get_int(settings, "rank")
    bg_type = obs.obs_data_get_string(settings, "bg_type")
    local bg_color_int = obs.obs_data_get_int(settings, "bg_color")
    local alpha = obs.obs_data_get_int(settings, "bg_alpha")
    local new_alpha = math.floor(alpha * 255 / 100)
    local rgb = bit.band(bg_color_int, 0x00FFFFFF)
    bg_color = int_to_css_color(bit.bor(bit.lshift(new_alpha, 24), rgb))
    bg_image = obs.obs_data_get_string(settings, "bg_image")
    local font_obj = obs.obs_data_get_obj(settings, "font")
    font = obs.obs_data_get_string(font_obj, "face")
    font_size_global = obs.obs_data_get_int(font_obj, "size")  -- получаем размер шрифта
    obs.obs_data_release(font_obj)
    local wins_color_int = obs.obs_data_get_int(settings, "wins_color")
    wins_color = int_to_css_color(wins_color_int)
    local losses_color_int = obs.obs_data_get_int(settings, "losses_color")
    losses_color = int_to_css_color(losses_color_int)
    local rank_text_color_int = obs.obs_data_get_int(settings, "rank_text_color")
    rank_text_color = int_to_css_color(rank_text_color_int)
    anim_direction = obs.obs_data_get_string(settings, "anim_direction")
    anim_duration_in = obs.obs_data_get_int(settings, "anim_duration_in")
    anim_stay_time = obs.obs_data_get_int(settings, "anim_stay_time")
    anim_duration_out = obs.obs_data_get_int(settings, "anim_duration_out")
    hidden_time = obs.obs_data_get_int(settings, "hidden_time")
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
  
    obs.obs_data_set_default_string(settings, "face", "Arial, sans-serif")
    obs.obs_data_set_default_int(settings, "size", 16)  -- можно задать нужный размер по умолчанию
    obs.obs_data_set_default_obj(settings, "font", settings)
   -- obs.obs_data_release(settings)
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
    local existing_widget = find_widget_source()
    if existing_widget then
        obs.script_log(obs.LOG_INFO, "Delayed init: найден существующий источник виджета.")
        widget_source = existing_widget
        update_widget_source()
    else
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
    local existing_widget = find_widget_source()
    if existing_widget then
        obs.script_log(obs.LOG_INFO, "Виджет уже существует. Обновляем его.")
        widget_source = existing_widget
        update_widget_source()
    else
        obs.script_log(obs.LOG_INFO, "Источник виджета не найден, запланирован Delayed Init...")
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

function script_save(settings)
    obs.obs_data_set_int(settings, "wins", wins)
    obs.obs_data_set_int(settings, "losses", losses)
    obs.obs_data_set_int(settings, "rank", rank)
    local hk_array = obs.obs_hotkey_save(hotkey_increase_wins_id)
    obs.obs_data_set_array(settings, "widget_increase_wins", hk_array)
    obs.obs_data_array_release(hk_array)
    hk_array = obs.obs_hotkey_save(hotkey_increase_losses_id)
    obs.obs_data_set_array(settings, "widget_increase_losses", hk_array)
    obs.obs_data_array_release(hk_array)
    hk_array = obs.obs_hotkey_save(hotkey_increase_rank_id)
    obs.obs_data_set_array(settings, "widget_increase_rank", hk_array)
    obs.obs_data_array_release(hk_array)
    hk_array = obs.obs_hotkey_save(hotkey_decrease_rank_id)
    obs.obs_data_set_array(settings, "widget_decrease_rank", hk_array)
    obs.obs_data_array_release(hk_array)
    hk_array = obs.obs_hotkey_save(hotkey_reset_stats_id)
    obs.obs_data_set_array(settings, "widget_reset_stats", hk_array)
    obs.obs_data_array_release(hk_array)
end

---------------------------------------------------
-- Функция script_unload – вызывается OBS при выгрузке скрипта
---------------------------------------------------
function script_unload()
    -- Останавливаем таймеры и горячие клавиши
    obs.timer_remove(delayed_init)
    stop_all_activity()

    -- Удаляем источник вручную
    if widget_source ~= nil then
        obs.obs_source_remove(widget_source) -- Удаляем из сцены
        obs.obs_source_release(widget_source) -- Освобождаем ссылку
        widget_source = nil
    end

    -- Освобождаем глобальные настройки, если они существуют
    if settings_global and obs.obs_data_valid(settings_global) then
        obs.obs_data_release(settings_global)
        settings_global = nil
    end

    collectgarbage("collect")
    obs.script_log(obs.LOG_INFO, "script_unload: Скрипт выгружен, ресурсы очищены, источник удалён.")
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
    stopped = true
    widget_source = nil
    if settings_global and obs.obs_data_valid(settings_global) then
        obs.obs_data_release(settings_global)
        settings_global = nil
    end
    collectgarbage("collect")
    obs.script_log(obs.LOG_INFO, "stop_script_and_delete_widget: Скрипт остановлен и виджет удалён безопасно.")
    return true
end