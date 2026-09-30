Учебный проект, Яндекс.Практикум: Анализ активности доноров крови
Стек: SQL ; объединение таблиц (LEFT JOIN, JOIN); CTE (WITH); оконные функции (SUM() OVER для расчёта долей); условная агрегация (FILTER, CASE); 
подзапросы и проверка существования (EXISTS); работа с датами (DATE_TRUNC, EXTRACT, INTERVAL); работа с пропусками и типами (COALESCE, NULLIF, 
IS DISTINCT FROM, ::text); статистические функции (PERCENTILE_CONT для медианы, AVG, GREATEST); UNION ALL (сведение каналов авторизации в одну 
таблицу); группировка и фильтрация (GROUP BY, HAVING, BETWEEN); проверка качества данных (пропуски, дубли, ошибочные даты, целостность связей 
между таблицами); оптимизация запросов (замена коррелированного подзапроса на JOIN по предагрегированным данным)



-- Размер таблиц
SELECT 'user_anon_data' AS table_name, COUNT(*) AS rows_count FROM donorsearch.user_anon_data
UNION ALL
SELECT 'donation_anon', COUNT(*) FROM donorsearch.donation_anon
UNION ALL
SELECT 'donation_plan', COUNT(*) FROM donorsearch.donation_plan
UNION ALL
SELECT 'user_anon_bonus', COUNT(*) FROM donorsearch.user_anon_bonus
UNION ALL
SELECT 'user_donation', COUNT(*) FROM donorsearch.user_donation
UNION ALL
SELECT 'events', COUNT(*) FROM donorsearch.events
UNION ALL
SELECT 'bs_data', COUNT(*) FROM donorsearch.bs_data;
-- table_name     |rows_count|
-- ---------------+----------+
-- user_anon_data |    265836|
-- donation_anon  |    245744|
-- donation_plan  |     27720|
-- user_anon_bonus|     21108|
-- user_donation  |      6231|
-- events         |      1536|
-- bs_data        |      1065|
-- В базе 265 836 доноров и 245 744 донации; таблицы планов, бонусов, мероприятий и центров заметно меньше.
-- Основной анализ строится на user_anon_data и donation_anon.


-- Дубликаты идентификаторов доноров (строки = уникальных id)
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT id) AS unique_ids
FROM donorsearch.user_anon_data;
-- total_rows|unique_ids|
-- ----------+----------+
--     265836|    265836|
-- Все 265 836 идентификаторов уникальны, дублей доноров нет.


-- Пропуски в ключевых столбцах user_anon_data
SELECT COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE region IS NULL OR TRIM(region) = '') AS region_empty,
       COUNT(*) FILTER (WHERE birth_date IS NULL) AS birth_date_null,
       COUNT(*) FILTER (WHERE registration_date IS NULL) AS registration_date_null,
       COUNT(*) FILTER (WHERE confirmed_donations IS NULL) AS confirmed_null,
       COUNT(*) FILTER (WHERE last_activity IS NULL) AS last_activity_null,
       COUNT(*) FILTER (WHERE blood_type IS NULL) AS blood_type_null
FROM donorsearch.user_anon_data;
-- total_rows|region_empty|birth_date_null|registration_date_null|confirmed_null|last_activity_null|blood_type_null|
-- ----------+------------+---------------+----------------------+--------------+------------------+---------------+
--     265836|      100574|         169325|                     0|             0|            173947|         212121|
-- Регион не указан у 100 574 доноров (38%), дата рождения - у 169 325 (64%), группа крови - у 212 121 (80%); дата регистрации заполнена у всех.
-- Поэтому анализ по возрасту и группе крови ненадёжен, а долю «Не указан» нужно учитывать при анализе регионов.
 
 
-- Аномалии в датах и счётчиках user_anon_data
SELECT MIN(birth_date) AS min_birth,
       MAX(birth_date) AS max_birth,
       COUNT(*) FILTER (WHERE birth_date < DATE '1930-01-01') AS too_old,
       COUNT(*) FILTER (WHERE birth_date > CURRENT_DATE - INTERVAL '18 years') AS under_18,
       MIN(registration_date) AS min_reg,
       MAX(registration_date) AS max_reg,
       MIN(last_activity) AS min_activity,
       MAX(last_activity) AS max_activity,
       COUNT(*) FILTER (WHERE last_activity < registration_date) AS activity_before_reg,
       MIN(confirmed_donations) AS min_confirmed,
       MAX(confirmed_donations) AS max_confirmed,
       COUNT(*) FILTER (WHERE confirmed_donations < 0 OR unconfirmed_donations < 0 OR donations_before_registration < 0) AS negative_counts
FROM donorsearch.user_anon_data;
-- min_birth |max_birth |too_old|under_18|min_reg   |max_reg   |min_activity|max_activity|activity_before_reg|min_confirmed|max_confirmed|negative_counts|
-- ----------+----------+-------+--------+----------+----------+------------+------------+-------------------+-------------+-------------+---------------+
-- 1888-09-22|2198-04-29|    200|     882|2018-04-09|2023-11-28|  2020-11-19|  2023-11-28|              11765|            0|          361|              0|
-- В датах рождения есть явные ошибки (от 1888 до 2198 года, 200 записей старше 1930-го), а у 11 765 доноров последняя активность раньше регистрации.
-- Отрицательных счётчиков нет, выгрузка сделана по 28.11.2023 (максимальные даты регистрации и активности).
 
 
-- Дубли столбцов: donations_before_registration и donations_of_time_registration (по описанию дублируют друг друга)
SELECT COUNT(*) FILTER (WHERE donations_before_registration IS DISTINCT FROM donations_of_time_registration) AS mismatch_rows
FROM donorsearch.user_anon_data;
-- mismatch_rows|
-- -------------+
--          2072|
-- Столбцы donations_before_registration и donations_of_time_registration расходятся лишь у 2 072 доноров (около 0,8%).
-- Для анализа достаточно использовать один из них.
 
 
-- Общая проверка donation_anon: период, пропуски, даты в будущем
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT id) AS unique_ids,
       MIN(donation_date) AS min_date,
       MAX(donation_date) AS max_date,
       COUNT(*) FILTER (WHERE donation_date IS NULL) AS date_null,
       COUNT(*) FILTER (WHERE user_id IS NULL) AS user_null,
       COUNT(*) FILTER (WHERE donation_date > CURRENT_DATE) AS future_dates
FROM donorsearch.donation_anon;
-- total_rows|unique_ids|min_date  |max_date  |date_null|user_null|future_dates|
-- ----------+----------+----------+----------+---------+---------+------------+
--     245744|    245744|0201-04-27|3016-03-28|        0|        0|          12|
-- В donation_anon есть невозможные даты (от 0201 до 3016 года), в том числе 12 донаций в будущем; пропусков нет, id уникальны.
-- Для анализа по времени период нужно ограничивать, как в задаче 2.
 
 
-- Донации без донора в user_anon_data (нарушение связи по внешнему ключу)
SELECT COUNT(*) AS orphan_donations
FROM donorsearch.donation_anon d
LEFT JOIN donorsearch.user_anon_data u ON u.id = d.user_id
WHERE u.id IS NULL;
-- orphan_donations|
-- ----------------+
--                0|
-- Каждая донация связана с существующим донором, нарушений связи между таблицами нет.
 
 
-- Возможные дубли донаций (один донор, одна дата, один тип крови)
SELECT COUNT(*) AS duplicate_groups,
       COALESCE(SUM(cnt - 1), 0) AS extra_rows
FROM (
    SELECT user_id, donation_date, blood_class, COUNT(*) AS cnt
    FROM donorsearch.donation_anon
    GROUP BY user_id, donation_date, blood_class
    HAVING COUNT(*) > 1
) t;
-- duplicate_groups|extra_rows|
-- ----------------+----------+
--             4245|     22965|
-- Найдено 4 245 групп повторов (тот же донор, дата и тип крови) - это 22 965 лишних строк, около 9% таблицы.
-- Донации могут быть слегка завышены, поэтому проверяем, какие статусы у таких дублей (запрос 0.8b).

-- Статусы строк, входящих в дубли
SELECT donation_status,
       COUNT(*) AS rows_in_duplicate_groups
FROM donorsearch.donation_anon d
WHERE EXISTS (
    SELECT 1
    FROM donorsearch.donation_anon d2
    WHERE d2.user_id = d.user_id
      AND d2.donation_date = d.donation_date
      AND d2.blood_class = d.blood_class
      AND d2.id <> d.id
)
GROUP BY donation_status
ORDER BY rows_in_duplicate_groups DESC;
-- donation_status|rows_in_duplicate_groups|
-- ---------------+------------------------+
-- Принята        |                   23075|
-- Удалена        |                    3369|
-- Без справки    |                     612|
-- Отклонена      |                     151|
-- На модерации   |                       3|
-- Почти 85% строк в дублях (23 075 из 27 210) имеют статус «Принята», а удалённых и отклонённых лишь около 13%, поэтому исключение этих статусов дубли не устранит.
-- В основном анализе дубли не убирались, так что абсолютное число донаций может быть завышено примерно на 9%, но сравнение периодов и групп это вряд ли сильно меняет.
 
 
-- Значения категориальных полей donation_anon
SELECT donation_status, COUNT(*) AS cnt
FROM donorsearch.donation_anon
GROUP BY donation_status
ORDER BY cnt DESC;
-- donation_status|cnt   |
-- ---------------+------+
-- Принята        |221506|
-- Без справки    | 17376|
-- Удалена        |  5478|
-- Отклонена      |  1285|
-- На модерации   |    99|
-- 90% донаций имеют статус «Принята», ещё 7% - «Без справки»; «Удалена» и «Отклонена» вместе около 2,8%.
-- Для подсчёта фактических донаций разумно исключать удалённые и отклонённые.
 
SELECT confirmation, COUNT(*) AS cnt
FROM donorsearch.donation_anon
GROUP BY confirmation
ORDER BY cnt DESC;
-- confirmation|cnt   |
-- ------------+------+
-- true        |229644|
-- false       | 16100|
-- Справка есть у 93% донаций (229 644), без справки - 16 100.
-- Подтверждённых больше, чем донаций со статусом «Принята», значит confirmation и donation_status считаются по-разному.
 
SELECT donation_type, COUNT(*) AS cnt
FROM donorsearch.donation_anon
GROUP BY donation_type
ORDER BY cnt DESC;
-- donation_type|cnt   |
-- -------------+------+
-- Безвозмездно |228515|
-- Платно       | 17229|
-- 93% донаций безвозмездные (228 515), платных - 17 229; в поле только два значения, как и в описании.
 
SELECT blood_class, COUNT(*) AS cnt
FROM donorsearch.donation_anon
GROUP BY blood_class
ORDER BY cnt DESC;
-- blood_class            |cnt   |
-- -----------------------+------+
-- Цельная кровь          |161768|
-- Плазма                 | 58488|
-- Тромбоциты             | 24957|
-- Эритроциты             |   446|
-- Гранулоциты (Лейкоциты)|    85|
-- Больше всего цельной крови (66%), затем плазма (24%) и тромбоциты (10%); эритроцитов и гранулоцитов совсем мало.
-- Значения корректные, но для отдельного анализа редких компонентов данных недостаточно.
 
 
-- Проверка donation_plan: статусы, период, пропуски
SELECT plan_status,
       COUNT(*) AS cnt,
       MIN(donation_date) AS min_donation_date,
       MAX(donation_date) AS max_donation_date,
       COUNT(*) FILTER (WHERE user_id IS NULL OR donation_date IS NULL) AS key_nulls
FROM donorsearch.donation_plan
GROUP BY plan_status
ORDER BY cnt DESC;
-- plan_status|cnt  |min_donation_date|max_donation_date|key_nulls|
-- -----------+-----+-----------------+-----------------+---------+
-- false      |15839|       2020-11-20|       2100-07-30|        0|
-- true       |11881|       2020-11-20|       2024-01-08|        0|
-- Статусов плана два: false (15 839) и true (11 881), пропусков в ключевых полях нет.
-- У false встречаются даты вплоть до 2100 года (ошибки или очень далёкие планы), а true заканчивается 08.01.2024.
 
 
-- Согласованность бонусов: count_bonuses_taken в user_anon_data и число строк в user_anon_bonus
SELECT COUNT(*) AS users_with_bonus_flag,
       COUNT(*) FILTER (WHERE COALESCE(b.bonus_rows, 0) = 0) AS no_rows_in_bonus_table,
       COUNT(*) FILTER (WHERE b.bonus_rows IS NOT NULL AND b.bonus_rows <> u.count_bonuses_taken) AS count_mismatch
FROM donorsearch.user_anon_data u
LEFT JOIN (
    SELECT user_id, COUNT(*) AS bonus_rows
    FROM donorsearch.user_anon_bonus
    GROUP BY user_id
) b ON b.user_id = u.id
WHERE u.count_bonuses_taken > 0;
-- users_with_bonus_flag|no_rows_in_bonus_table|count_mismatch|
-- ---------------------+----------------------+--------------+
--                  9345|                     0|             0|
-- У всех 9 345 доноров с бонусами есть строки в user_anon_bonus, а число строк совпадает с count_bonuses_taken - таблицы согласованы.
 
 
-- Согласованность confirmed_donations и подтверждённых донаций в donation_anon
SELECT COUNT(*) AS donors,
       COUNT(*) FILTER (WHERE u.confirmed_donations = COALESCE(d.cnt, 0)) AS equal_rows,
       COUNT(*) FILTER (WHERE u.confirmed_donations > COALESCE(d.cnt, 0)) AS profile_more,
       COUNT(*) FILTER (WHERE u.confirmed_donations < COALESCE(d.cnt, 0)) AS profile_less
FROM donorsearch.user_anon_data u
LEFT JOIN (
    SELECT user_id, COUNT(*) AS cnt
    FROM donorsearch.donation_anon
    WHERE confirmation IS TRUE
    GROUP BY user_id
) d ON d.user_id = u.id;
-- donors|equal_rows|profile_more|profile_less|
-- ------+----------+------------+------------+
-- 265836|    259860|        1073|        4903|
-- У 97,7% доноров confirmed_donations совпадает с числом подтверждённых донаций в таблице; расхождения есть у 5 976 доноров (2,2%).
-- Для топа доноров имеет смысл смотреть оба источника.


-- 1. РЕГИОНЫ С НАИБОЛЬШИМ КОЛИЧЕСТВОМ ЗАРЕГИСТРИРОВАННЫХ ДОНОРОВ

-- ТОП-10 регионов (пустой регион выделяем отдельной строкой, чтобы он не терялся)
SELECT COALESCE(NULLIF(TRIM(region), ''), 'Не указан') AS region,
       COUNT(*) AS donors,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM donorsearch.user_anon_data
GROUP BY COALESCE(NULLIF(TRIM(region), ''), 'Не указан')
ORDER BY donors DESC
LIMIT 10;
-- region                                    |donors|percentage|
-- ------------------------------------------+------+----------+
-- Не указан                                 |100574|     37.83|
-- Россия, Москва                            | 37819|     14.23|
-- Россия, Санкт-Петербург                   | 13137|      4.94|
-- Россия, Татарстан, Казань                 |  6610|      2.49|
-- Украина, Киевская область, Киев           |  3541|      1.33|
-- Россия, Новосибирская область, Новосибирск|  3310|      1.25|
-- Россия, Свердловская область, Екатеринбург|  3082|      1.16|
-- Россия, Башкортостан, Уфа                 |  3014|      1.13|
-- Россия, Красноярский край, Красноярск     |  2346|      0.88|
-- Россия, Краснодарский край, Краснодар     |  2186|      0.82|
-- Больше всего доноров в Москве (37 819, 14%) и Санкт-Петербурге (13 137, 5%), далее Казань, Киев и Новосибирск.
-- У 38% регион не указан; среди указавших регион доля Москвы около 23%.
 
 
-- 2. ДИНАМИКА ДОНАЦИЙ ПО МЕСЯЦАМ В 2022 И 2023 ГОДАХ
 
-- 2.1 По месяцам подряд (удобно для графика)
SELECT DATE_TRUNC('month', donation_date)::date AS month,
       COUNT(*) AS donations
FROM donorsearch.donation_anon
WHERE donation_date >= DATE '2022-01-01'
  AND donation_date < DATE '2024-01-01'
GROUP BY DATE_TRUNC('month', donation_date)
ORDER BY month;
-- РЕЗУЛЬТАТ: (вставь заново - в исходном файле здесь по ошибке была скопирована таблица из задачи 1)
-- В 2022 году донаций в целом становилось больше (с 1 977 в январе до 3 303 в декабре), в 2023 году пик пришёлся на март (3 523), после чего число снижалось до 1 509 в ноябре.
-- Данных за декабрь 2023 нет, а ноябрь неполный (выгрузка по 28.11.2023).

-- 2.2 Сравнение одноимённых месяцев 2022 и 2023 и изменение в %
SELECT EXTRACT(MONTH FROM donation_date)::int AS month_num,
       COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM donation_date) = 2022) AS donations_2022,
       COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM donation_date) = 2023) AS donations_2023,
       ROUND(
           (COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM donation_date) = 2023)
            - COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM donation_date) = 2022)) * 100.0
           / NULLIF(COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM donation_date) = 2022), 0), 1
       ) AS change_pct
FROM donorsearch.donation_anon
WHERE donation_date >= DATE '2022-01-01'
  AND donation_date < DATE '2024-01-01'
GROUP BY EXTRACT(MONTH FROM donation_date)
ORDER BY month_num;
-- month_num|donations_2022|donations_2023|change_pct|
-- ---------+--------------+--------------+----------+
--         1|          1977|          2795|      41.4|
--         2|          2109|          3056|      44.9|
--         3|          3002|          3523|      17.4|
--         4|          3223|          2951|      -8.4|
--         5|          2414|          2568|       6.4|
--         6|          2792|          2651|      -5.1|
--         7|          2836|          2276|     -19.7|
--         8|          2987|          2433|     -18.5|
--         9|          3089|          2240|     -27.5|
--        10|          3265|          2117|     -35.2|
--        11|          3156|          1509|     -52.2|
--        12|          3303|             0|    -100.0|
-- В 2022 году число донаций в целом росло от 1 977 в январе до 3 303 в декабре, а в 2023 году достигло пика в марте (3 523) и снизилось до 1 509 в ноябре.
-- В январе-марте 2023 года донаций на 17-45% больше, чем годом ранее, в апреле-ноябре - меньше; декабрь 2023 сравнить нельзя, данных нет.
-- За первое полугодие в 2023 году донаций примерно на 13% больше (17 544 против 15 517), поэтому спад во втором полугодии может быть частично связан с неполнотой выгрузки.
 
-- 2.3 Итоги по годам
SELECT EXTRACT(YEAR FROM donation_date)::int AS year,
       COUNT(*) AS donations
FROM donorsearch.donation_anon
WHERE donation_date >= DATE '2022-01-01'
  AND donation_date < DATE '2024-01-01'
GROUP BY EXTRACT(YEAR FROM donation_date)
ORDER BY year;
-- year|donations|
-- ----+---------+
-- 2022|    34153|
-- 2023|    28119|
-- В 2022 году зафиксировано 34 153 донации, в 2023 - 28 119 (-17,7%), но 2023 год неполный: нет декабря и части ноября.
-- Для одинаковых периодов (январь-ноябрь) спад около 9% (28 119 против 30 850).
 

-- 3. НАИБОЛЕЕ АКТИВНЫЕ ДОНОРЫ (только подтверждённые донации, сделанные через сайт)

-- 3.1 ТОП-10 по полю confirmed_donations
SELECT id,
       gender,
       region,
       confirmed_donations,
       donations_before_registration,
       registration_date
FROM donorsearch.user_anon_data
WHERE confirmed_donations IS NOT NULL
ORDER BY confirmed_donations DESC, id
LIMIT 10;
-- id    |gender |region                                                            |confirmed_donations|donations_before_registration|registration_date|
-- ------+-------+------------------------------------------------------------------+-------------------+-----------------------------+-----------------+
-- 235391|Мужской|Россия, Татарстан, Казань                                         |                361|                             |       2022-12-14|
-- 273317|Женский|Россия, Санкт-Петербург                                           |                257|                          190|       2023-10-27|
-- 201521|Мужской|Россия, Ивановская область, Иваново                               |                236|                          200|       2022-04-28|
-- 211970|Мужской|Россия, Иркутская область, Иркутск                                |                236|                             |       2022-07-22|
-- 132946|Мужской|Россия, Белгородская область, Белгород                            |                227|                             |       2018-04-09|
--  53912|Мужской|Россия, Кировская область, Кирово-Чепецк                          |                217|                          190|       2018-04-09|
-- 216353|Мужской|Россия, Тамбовская область, Тамбов                                |                216|                          185|       2022-08-20|
-- 233686|Мужской|Россия, Ханты-Мансийский Автономный округ - Югра АО, Нижневартовск|                215|                             |       2022-12-01|
-- 204073|Мужской|Россия, Красноярский край, Красноярск                             |                213|                          200|       2022-05-23|
-- 267054|Мужской|Россия, Самарская область, Сызрань                                |                209|                          209|       2023-08-21|
-- Самый активный донор - id 235391 (361 подтверждённая донация, Казань), у остальных из топ-10 от 209 до 257 донаций; девять из десяти - мужчины из разных регионов.
-- У шести из десяти указано 185-209 донаций до регистрации на сайте, то есть значительная часть донаций сделана ещё до регистрации.
 
-- 3.2 Перепроверка по таблице донаций (только донации с подтверждающей справкой)
SELECT user_id,
       COUNT(*) AS confirmed_donations_check,
       MIN(donation_date) AS first_donation,
       MAX(donation_date) AS last_donation
FROM donorsearch.donation_anon
WHERE confirmation IS TRUE
GROUP BY user_id
ORDER BY confirmed_donations_check DESC, user_id
LIMIT 10;
-- user_id|confirmed_donations_check|first_donation|last_donation|
-- -------+-------------------------+--------------+-------------+
--  235391|                      361|    1975-01-01|   2023-11-03|
--  201521|                      236|    2011-03-10|   2023-11-15|
--  211970|                      236|    2009-03-13|   2022-08-01|
--  132946|                      227|    2007-02-15|   2019-07-17|
--  216353|                      217|    2009-09-29|   2023-10-05|
--   53912|                      216|    1996-07-18|   2023-11-18|
--  233686|                      215|    2004-08-09|   2008-01-29|
--  204073|                      213|    2003-12-03|   2023-11-07|
--  267054|                      209|    2008-08-16|   2023-08-25|
--  229012|                      204|    2002-05-20|   2023-10-20|
-- По таблице донаций лидеры почти те же (361, 236, 236, 227...), то есть поле confirmed_donations в целом надёжно.
-- Отличия небольшие: донора 273317 в этом топе нет (вероятно, его донации до регистрации не хранятся строками), зато появился 229012; дата 1975-01-01 у лидера похожа на условную.
 
 
-- 4. ВЛИЯНИЕ СИСТЕМЫ БОНУСОВ НА ДОНАЦИИ
 
-- 4.1 Сравнение доноров, использовавших и не использовавших бонусы
SELECT CASE WHEN count_bonuses_taken > 0 THEN 'Использовали бонусы' ELSE 'Не использовали бонусы' END AS bonus_group,
       COUNT(*) AS donors,
       ROUND(AVG(confirmed_donations), 2) AS avg_confirmed,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY confirmed_donations) AS median_confirmed
FROM donorsearch.user_anon_data
WHERE confirmed_donations IS NOT NULL
GROUP BY CASE WHEN count_bonuses_taken > 0 THEN 'Использовали бонусы' ELSE 'Не использовали бонусы' END;
-- bonus_group           |donors|avg_confirmed|median_confirmed|
-- ----------------------+------+-------------+----------------+
-- Использовали бонусы   |  9345|         9.44|             2.0|
-- Не использовали бонусы|256491|         0.53|             0.0|
-- Доноры, использовавшие бонусы, в среднем имеют 9,44 подтверждённой донации против 0,53 у остальных (медиана 2 против 0).
-- Таких доноров немного (9 345, около 3,5%), но они заметно активнее.
 
-- 4.2 Зависит ли число донаций от числа использованных бонусов
SELECT CASE
           WHEN count_bonuses_taken = 0 THEN '0'
           WHEN count_bonuses_taken BETWEEN 1 AND 2 THEN '1-2'
           WHEN count_bonuses_taken BETWEEN 3 AND 5 THEN '3-5'
           ELSE '6+'
       END AS bonuses_bin,
       COUNT(*) AS donors,
       ROUND(AVG(confirmed_donations), 2) AS avg_confirmed
FROM donorsearch.user_anon_data
WHERE confirmed_donations IS NOT NULL
GROUP BY CASE
             WHEN count_bonuses_taken = 0 THEN '0'
             WHEN count_bonuses_taken BETWEEN 1 AND 2 THEN '1-2'
             WHEN count_bonuses_taken BETWEEN 3 AND 5 THEN '3-5'
             ELSE '6+'
         END
ORDER BY MIN(count_bonuses_taken);
-- bonuses_bin|donors|avg_confirmed|
-- -----------+------+-------------+
-- 0          |256491|         0.53|
-- 1-2        |  6967|         7.39|
-- 3-5        |  1746|        13.14|
-- 6+         |   632|        21.80|
-- Чем больше использовано бонусов, тем выше средняя активность: 7,39 донации при 1-2 бонусах, 13,14 при 3-5 и 21,80 при 6 и более.
-- Связь сильная, но она не доказывает причинность: бонусы могут получать те, кто и так донорствует регулярно.
 
-- 4.3 Подтверждённые донации до и после первого использования бонуса
WITH first_bonus AS (
    SELECT user_id,
           MIN(date_of_use) AS first_bonus_date
    FROM donorsearch.user_anon_bonus
    WHERE date_of_use IS NOT NULL
    GROUP BY user_id
)
SELECT COUNT(DISTINCT fb.user_id) AS donors,
       COUNT(*) FILTER (WHERE d.donation_date < fb.first_bonus_date) AS donations_before_bonus,
       COUNT(*) FILTER (WHERE d.donation_date >= fb.first_bonus_date) AS donations_after_bonus,
       ROUND(COUNT(*) FILTER (WHERE d.donation_date < fb.first_bonus_date) * 1.0 / COUNT(DISTINCT fb.user_id), 2) AS avg_before,
       ROUND(COUNT(*) FILTER (WHERE d.donation_date >= fb.first_bonus_date) * 1.0 / COUNT(DISTINCT fb.user_id), 2) AS avg_after
FROM first_bonus fb
JOIN donorsearch.donation_anon d ON d.user_id = fb.user_id
WHERE d.confirmation IS TRUE;
-- donors|donations_before_bonus|donations_after_bonus|avg_before|avg_after|
-- ------+----------------------+---------------------+----------+---------+
--   9306|                 71562|                16308|      7.69|     1.75|
-- До первого бонуса в среднем 7,69 донации на донора, после - 1,75, но периоды несопоставимы: «до» включает всю историю (в том числе годы до регистрации), а «после» ограничено датой выгрузки.
-- Запрос скорее показывает, что бонусы получают уже опытные доноры, а не что активность падает.
 

-- 5. ВОВЛЕЧЕНИЕ ДОНОРОВ ЧЕРЕЗ СОЦИАЛЬНЫЕ СЕТИ И СЕРВИСЫ

-- 5.1 Количество доноров и среднее число подтверждённых донаций по каждому каналу авторизации
-- (донор с несколькими привязками попадает в несколько каналов, поэтому сумма доноров может быть больше общего числа)
WITH channels AS (
    SELECT 'ВКонтакте' AS channel, id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE autho_vk IS TRUE
    UNION ALL
    SELECT 'Одноклассники', id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE autho_ok IS TRUE
    UNION ALL
    SELECT 'Telegram', id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE autho_tg IS TRUE
    UNION ALL
    SELECT 'Яндекс ID', id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE autho_yandex IS TRUE
    UNION ALL
    SELECT 'Google', id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE autho_google IS TRUE
    UNION ALL
    SELECT 'Без привязки соцсетей', id, confirmed_donations
    FROM donorsearch.user_anon_data
    WHERE NOT (COALESCE(autho_vk, FALSE) OR COALESCE(autho_ok, FALSE) OR COALESCE(autho_tg, FALSE)
               OR COALESCE(autho_yandex, FALSE) OR COALESCE(autho_google, FALSE))
)
SELECT channel,
       COUNT(*) AS donors,
       ROUND(AVG(confirmed_donations), 2) AS avg_confirmed
FROM channels
GROUP BY channel
ORDER BY donors DESC;
-- channel              |donors|avg_confirmed|
-- ---------------------+------+-------------+
-- ВКонтакте            |127254|         0.91|
-- Без привязки соцсетей|113266|         0.71|
-- Google               | 16485|         2.22|
-- Одноклассники        |  7766|         1.72|
-- Яндекс ID            |  5170|         3.90|
-- Telegram             |   890|         4.32|
-- Самые массовые каналы - ВКонтакте (127 254) и вход без привязки соцсетей (113 266), но средняя активность там низкая (0,91 и 0,71 донации).
-- Доноры с Telegram (4,32), Яндекс ID (3,90) и Google (2,22) сдают заметно чаще, хотя их гораздо меньше; один донор может входить в несколько каналов.
 
-- 5.2 Сколько каналов привязывают доноры и как это связано с активностью
SELECT (COALESCE(autho_vk, FALSE)::int + COALESCE(autho_ok, FALSE)::int + COALESCE(autho_tg, FALSE)::int
        + COALESCE(autho_yandex, FALSE)::int + COALESCE(autho_google, FALSE)::int) AS channels_linked,
       COUNT(*) AS donors,
       ROUND(AVG(confirmed_donations), 2) AS avg_confirmed
FROM donorsearch.user_anon_data
GROUP BY channels_linked
ORDER BY channels_linked;
-- channels_linked|donors|avg_confirmed|
-- ---------------+------+-------------+
--               0|113266|         0.71|
--               1|148655|         0.75|
--               2|  3054|         6.63|
--               3|   686|        11.75|
--               4|   131|        16.80|
--               5|    44|        24.39|
-- Одна привязка почти не отличается от нуля (0,75 против 0,71 донации), а при двух и больше активность резко растёт: 6,63 при двух каналах и 24,39 при пяти.
-- Вероятно, активные доноры чаще пользуются сайтом и привязывают больше аккаунтов, а не наоборот.
 

-- 6. ОДНОКРАТНЫЕ И ПОВТОРНЫЕ ДОНОРЫ
 
-- 6.1 Размер групп и средние показатели (по подтверждённым донациям, только доноры хотя бы с одной донацией)
SELECT CASE WHEN confirmed_donations = 1 THEN 'Однократные' ELSE 'Повторные (2+)' END AS donor_type,
       COUNT(*) AS donors,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
       ROUND(AVG(confirmed_donations), 2) AS avg_confirmed,
       ROUND(AVG(last_activity - registration_date), 1) AS avg_days_between_reg_and_last_activity
FROM donorsearch.user_anon_data
WHERE confirmed_donations >= 1
GROUP BY CASE WHEN confirmed_donations = 1 THEN 'Однократные' ELSE 'Повторные (2+)' END;
-- donor_type    |donors|percentage|avg_confirmed|avg_days_between_reg_and_last_activity|
-- --------------+------+----------+-------------+--------------------------------------+
-- Однократные   | 19510|     50.50|         1.00|                                 222.6|
-- Повторные (2+)| 19127|     49.50|        10.63|                                 642.3|
-- Однократных и повторных доноров поровну (50,5% и 49,5%).
-- Повторные в среднем сдали 10,63 донации и остаются на сайте около 642 дней против 223 у однократных.
 
-- 6.2 Активность повторных доноров: донаций в год и средний интервал между донациями
WITH user_stats AS (
    SELECT user_id,
           COUNT(*) AS donations,
           MIN(donation_date) AS first_donation,
           MAX(donation_date) AS last_donation
    FROM donorsearch.donation_anon
    WHERE confirmation IS TRUE
    GROUP BY user_id
)
SELECT CASE WHEN donations = 1 THEN 'Однократные' ELSE 'Повторные (2+)' END AS donor_type,
       COUNT(*) AS donors,
       ROUND(AVG(donations), 2) AS avg_donations,
       ROUND(AVG(donations / GREATEST((last_donation - first_donation) / 365.0, 1)), 2) AS avg_donations_per_year,
       ROUND(AVG((last_donation - first_donation) * 1.0 / NULLIF(donations - 1, 0)), 1) AS avg_days_between_donations
FROM user_stats
GROUP BY CASE WHEN donations = 1 THEN 'Однократные' ELSE 'Повторные (2+)' END;
-- donor_type    |donors|avg_donations|avg_donations_per_year|avg_days_between_donations|
-- --------------+------+-------------+----------------------+--------------------------+
-- Повторные (2+)| 20033|        10.42|                  3.30|                     201.8|
-- Однократные   | 20946|         1.00|                  1.00|                          |
-- Повторные доноры сдают в среднем 3,3 донации в год с интервалом около 202 дней (примерно раз в 6-7 месяцев); у однократных по определению одна донация.
-- Размеры групп отличаются от 6.1, потому что здесь считаются строки в таблице донаций, а не счётчик из анкеты.
 

-- 7. ПЛАНИРУЕМЫЕ И ФАКТИЧЕСКИЕ ДОНАЦИИ
-- Факт донации сводится к уникальным парам (донор, дата) и присоединяется к планам одним JOIN.
-- Период ограничен датами, покрытыми данными (20.11.2020 - 28.11.2023), удалённые донации не учитываются.

-- 7.1 Доля планов, которые закончились фактической донацией (совпадение по донору и дате)
WITH fact AS (
    SELECT DISTINCT user_id, donation_date
    FROM donorsearch.donation_anon
    WHERE donation_status IS DISTINCT FROM 'Удалена'
      AND donation_date BETWEEN DATE '2020-11-20' AND DATE '2023-11-28'
),
plans AS (
    SELECT p.id,
           p.plan_status,
           (f.user_id IS NOT NULL) AS is_done
    FROM donorsearch.donation_plan p
    LEFT JOIN fact f
           ON f.user_id = p.user_id
          AND f.donation_date = p.donation_date
    WHERE p.donation_date BETWEEN DATE '2020-11-20' AND DATE '2023-11-28'
)
SELECT plan_status::text AS plan_status,
       COUNT(*) AS planned,
       COUNT(*) FILTER (WHERE is_done) AS done,
       ROUND(COUNT(*) FILTER (WHERE is_done) * 100.0 / COUNT(*), 2) AS conversion_pct
FROM plans
GROUP BY plan_status
UNION ALL
SELECT 'Все планы',
       COUNT(*),
       COUNT(*) FILTER (WHERE is_done),
       ROUND(COUNT(*) FILTER (WHERE is_done) * 100.0 / COUNT(*), 2)
FROM plans;
-- plan_status|planned|done|conversion_pct|
-- -----------+-------+----+--------------+
-- false      |  15198| 354|          2.33|
-- true       |  11880|5217|         43.91|
-- Все планы  |  27078|5571|         20.57|
-- Из 27 078 планов на фактическую донацию в запланированный день закончились 5 571 (20,6%).
-- У планов со статусом true доля совпадений 43,9%, у false - всего 2,3%, то есть статус хорошо отделяет реализуемые планы от нереализованных.
-- Даже у true совпадает меньше половины планов, потому что дата донации часто сдвигается (см. 7.4).

-- 7.2 Конверсия планов по месяцам
WITH fact AS (
    SELECT DISTINCT user_id, donation_date
    FROM donorsearch.donation_anon
    WHERE donation_status IS DISTINCT FROM 'Удалена'
      AND donation_date BETWEEN DATE '2020-11-20' AND DATE '2023-11-28'
),
plans AS (
    SELECT p.donation_date,
           (f.user_id IS NOT NULL) AS is_done
    FROM donorsearch.donation_plan p
    LEFT JOIN fact f
           ON f.user_id = p.user_id
          AND f.donation_date = p.donation_date
    WHERE p.donation_date BETWEEN DATE '2020-11-20' AND DATE '2023-11-28'
)
SELECT DATE_TRUNC('month', donation_date)::date AS month,
       COUNT(*) AS planned,
       COUNT(*) FILTER (WHERE is_done) AS done,
       ROUND(COUNT(*) FILTER (WHERE is_done) * 100.0 / COUNT(*), 2) AS conversion_pct
FROM plans
GROUP BY DATE_TRUNC('month', donation_date)
ORDER BY month;
-- month     |planned|done|conversion_pct|
-- ----------+-------+----+--------------+
-- 2020-11-01|     43|   9|         20.93|
-- 2020-12-01|    107|  26|         24.30|
-- 2021-01-01|    112|  29|         25.89|
-- 2021-02-01|    194|  52|         26.80|
-- 2021-03-01|    256|  56|         21.88|
-- 2021-04-01|    260|  53|         20.38|
-- 2021-05-01|    216|  46|         21.30|
-- 2021-06-01|    356|  66|         18.54|
-- 2021-07-01|    244|  50|         20.49|
-- 2021-08-01|    277|  45|         16.25|
-- 2021-09-01|    431|  80|         18.56|
-- 2021-10-01|    385|  57|         14.81|
-- 2021-11-01|    505|  81|         16.04|
-- 2021-12-01|    621| 116|         18.68|
-- 2022-01-01|    468|  78|         16.67|
-- 2022-02-01|    476|  76|         15.97|
-- 2022-03-01|    601| 125|         20.80|
-- 2022-04-01|   1027| 173|         16.85|
-- 2022-05-01|    645| 142|         22.02|
-- 2022-06-01|   1079| 175|         16.22|
-- 2022-07-01|    693| 148|         21.36|
-- 2022-08-01|    822| 180|         21.90|
-- 2022-09-01|   1043| 171|         16.40|
-- 2022-10-01|   1209| 221|         18.28|
-- 2022-11-01|   1184| 222|         18.75|
-- 2022-12-01|   1351| 263|         19.47|
-- 2023-01-01|    961| 228|         23.73|
-- 2023-02-01|   1100| 281|         25.55|
-- 2023-03-01|   1401| 328|         23.41|
-- 2023-04-01|   1512| 296|         19.58|
-- 2023-05-01|   1203| 243|         20.20|
-- 2023-06-01|   1056| 271|         25.66|
-- 2023-07-01|    847| 219|         25.86|
-- 2023-08-01|   1064| 247|         23.21|
-- 2023-09-01|   1103| 274|         24.84|
-- 2023-10-01|   1261| 241|         19.11|
-- 2023-11-01|    965| 203|         21.04|
-- Число планов выросло с десятков в конце 2020 года до 1 000-1 500 в месяц в 2022-2023 годах, то есть функцией планирования стали пользоваться заметно чаще.
-- Ежемесячная доля выполненных планов колеблется в диапазоне 15-27% без устойчивого тренда; по годам она составила около 19,0% в 2021, 18,6% в 2022 и 22,7% в 2023 году.
-- Рост эффективности планирования в 2023 году есть, но небольшой: примерно каждый пятый план заканчивается донацией в запланированный день.

-- 7.3 Какая доля всех фактических донаций была запланирована заранее на сайте
SELECT COUNT(*) AS all_donations,
       COUNT(*) FILTER (WHERE plan_date IS NOT NULL) AS with_plan_date,
       ROUND(COUNT(*) FILTER (WHERE plan_date IS NOT NULL) * 100.0 / COUNT(*), 2) AS planned_share_pct
FROM donorsearch.donation_anon;
-- all_donations|with_plan_date|planned_share_pct|
-- -------------+--------------+-----------------+
--        245744|          8870|             3.61|
-- Только 8 870 донаций из 245 744 (3,61%) были заранее запланированы на сайте; подавляющая часть донаций фиксируется без планирования.

-- 7.4 Насколько фактическая дата совпадает с плановой (для донаций, у которых указан plan_date)
SELECT COUNT(*) AS planned_donations,
       COUNT(*) FILTER (WHERE donation_date = plan_date) AS same_day,
       COUNT(*) FILTER (WHERE ABS(donation_date - plan_date) BETWEEN 1 AND 7) AS shifted_up_to_7_days,
       COUNT(*) FILTER (WHERE ABS(donation_date - plan_date) > 7) AS shifted_more_than_7_days,
       ROUND(COUNT(*) FILTER (WHERE donation_date = plan_date) * 100.0 / COUNT(*), 2) AS same_day_pct
FROM donorsearch.donation_anon
WHERE plan_date IS NOT NULL
  AND donation_date BETWEEN DATE '2020-11-20' AND DATE '2023-11-28';
-- planned_donations|same_day|shifted_up_to_7_days|shifted_more_than_7_days|same_day_pct|
-- -----------------+--------+--------------------+------------------------+------------+
--              8808|    5273|                1050|                    2485|       59.87|
-- Из 8 808 донаций с указанной плановой датой 59,9% состоялись точно в назначенный день, ещё 11,9% - со сдвигом до недели.
-- Для 28,2% донаций дата отличается от плановой более чем на 7 дней, то есть планы часто переносятся.




-- ОБЩИЙ ВЫВОД ПО АНАЛИЗУ

-- Качество данных. Данные в целом согласованы (нет дублей доноров и «осиротевших» донаций, бонусы сходятся между таблицами),
-- но есть пропуски (регион не указан у 38% доноров, дата рождения - у 64%) и ошибочные даты (от 0201 до 3016 года),
-- а также около 9% строк-дублей в таблице донаций. Поэтому анализ проводился на очищенных периодах.
-- Регионы. Доноры сосредоточены в крупных городах: Москва (14% всех и около 23% среди указавших регион) и Санкт-Петербург (5%),
-- далее Казань, Киев, Новосибирск и Екатеринбург.
-- Динамика. В 2022 году число донаций росло (с 1 977 в январе до 3 303 в декабре), в 2023 году пик пришёлся на март, после чего наблюдался спад.
-- Часть спада объясняется неполнотой выгрузки (нет декабря 2023): за первое полугодие донаций в 2023 году на 13% больше, чем в 2022.
-- Активные доноры. Лидеры набрали 209-361 подтверждённую донацию; значительная часть их донаций сделана до регистрации на сайте.
-- Бонусы. Доноры, использовавшие бонусы, заметно активнее (в среднем 9,44 донации против 0,53) и чем больше бонусов, тем выше активность.
-- Это связь, а не доказанное влияние: бонусы могут получать уже опытные доноры.
-- Соцсети. Основные каналы входа - ВКонтакте и без привязки, но самые активные доноры привязывают Telegram, Яндекс ID и Google,
-- а активность резко растёт при двух и более привязанных аккаунтах (6,63 донации при двух, 24,39 при пяти).
-- Однократные и повторные доноры. Их поровну (50,5% и 49,5%); повторные сдают в среднем 10,6 донации, около 3,3 раза в год,
-- с интервалом примерно 200 дней и остаются на сайте втрое дольше (642 против 223 дней).
-- Планирование. Планами пользуются всё чаще, но только 20,6% планов заканчиваются донацией в запланированный день (43,9% для статуса true);
-- при этом 3,6% всех донаций были заранее запланированы на сайте, а 60% плановых донаций происходят точно в назначенную дату.
-- Рекомендации. Улучшить заполнение региона в анкете, поощрять привязку нескольких аккаунтов и переход от первой донации ко второй
-- (половина доноров остаётся однократными), напоминать о запланированной дате и предлагать перенос, а не отмену.