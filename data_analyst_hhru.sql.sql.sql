-- Учебный проект, Яндекс.Практикум: Анализ рынка вакансий для аналитиков данных
-- Стек: SQL; CTE (WITH); оконные функции (ROW_NUMBER() OVER (PARTITION BY ...), SUM() OVER); UNION ALL (приведение навыков 
-- из нескольких столбцов к одной таблице); агрегатные функции (COUNT, AVG, MIN, MAX, SUM, ROUND); группировка (GROUP BY); 
-- фильтрация и поиск по тексту (ILIKE, DISTINCT, LIMIT); проверка качества данных (поиск аномалий и выбросов)




-- Структура таблицы и пример строк
SELECT *
FROM public.parcing_table
LIMIT 5;
-- id       |name                         |published_at           |employer    |department        |area           |experience         |schedule   |employment      |salary_from|salary_to|salary_bin   |key_skills_1          |key_skills_2 |key_skills_3 |key_skills_4|soft_skills_1         |soft_skills_2|soft_skills_3 |soft_skills_4|
-- ---------+-----------------------------+-----------------------+------------+------------------+---------------+-------------------+-----------+----------------+-----------+---------+-------------+----------------------+-------------+-------------+------------+----------------------+-------------+--------------+-------------+
-- 100069131|Дата аналитик                |2024-05-24 13:05:01.000|СБЕР        |Сбер для экспертов|Санкт-Петербург|Junior+ (1-3 years)|Полный день|Полная занятость|           |         |ЗП не указана|Документация          |Проактивность|Коммуникация |            |Коммуникация          | Документация| Проактивность|             |
-- 100069821|Аналитик данных              |2024-06-10 16:49:49.000|МТС         |«МТС»             |Казань         |Junior+ (1-3 years)|Полный день|Полная занятость|    72000.0|         |ЗП не указана|                      |             |             |            |                      |             |              |             |
-- 100071014|Аналитик данных              |2024-06-07 11:08:22.000|Россети Урал|                  |Екатеринбург   |Junior+ (1-3 years)|Полный день|Полная занятость|    51000.0|         |ЗП не указана|Аналитическое мышление|             |             |            |Аналитическое мышление|             |              |             |
-- 100077503|Data Analyst                 |2024-05-24 14:14:00.000|СБЕР        |Сбер для экспертов|Москва         |Middle (3-6 years) |Полный день|Полная занятость|           |         |ЗП не указана|Pandas                |             |             |            |                      |             |              |             |
-- 100077910|Data Analyst / Data Scientist|2024-06-11 14:17:47.000|Итсен       |                  |Москва         |Middle (3-6 years) |Полный день|Полная занятость|   350000.0|         |ЗП не указана|Linux                 |SQL          |Бизнес-анализ|Hadoop      |Аналитическое мышление|             |              |             |
-- В таблице параметры вакансии, зарплата (от и до), а также по четыре hard и soft навыка в отдельных столбцах.
-- Есть пропуски в зарплате и навыках, а salary_bin в части строк показывает «ЗП не указана» даже при заполненной salary_from, поэтому зарплату считаем по salary_from и salary_to.

-- Общее количество строк
SELECT COUNT(*)
FROM public.parcing_table;
-- count|
-- -----+
--  1801|
-- В выборке 1 801 вакансия.

-- Количество уникальных названий вакансий
SELECT COUNT(DISTINCT name)
FROM public.parcing_table;
-- count|
-- -----+
--   763|
-- На 1 801 вакансию приходится 763 уникальных названия, то есть многие названия повторяются у разных работодателей.

-- Проверка, что все названия относятся к вакансиям аналитиков
SELECT COUNT(DISTINCT name)
FROM public.parcing_table
WHERE name ILIKE '%аналитик%'
   OR name ILIKE '%analyst%';
-- count|
-- -----+
--   763|
-- Количество совпало с предыдущим запросом: каждое название имеет отношение к вакансии аналитика, лишних вакансий в выборке нет.

-- Период публикации вакансий
SELECT MIN(DATE(published_at)) AS min_date,
       MAX(DATE(published_at)) AS max_date
FROM public.parcing_table;
-- min_date  |max_date  |
-- ----------+----------+
-- 2024-02-13|2024-06-11|
-- Данные охватывают период с 13 февраля по 11 июня 2024 года.

-- Формат записи навыков в столбцах soft_skills_2, soft_skills_3 и soft_skills_4
SELECT soft_skills_3
FROM public.parcing_table
WHERE soft_skills_3 ILIKE ' Аналитическое мышление';
-- В столбцах soft_skills_2–4 значения записаны с пробелом в начале.
-- При подсчёте по каждому столбцу отдельно это не мешает, а при объединении столбцов в общий список навыков значения нужно очищать функцией TRIM.




-- 1 СТАТИСТИКА ПО ПРЕДЛАГАЕМОЙ ЗАРАБОТНОЙ ПЛАТЕ 
SELECT ROUND(AVG(salary_from), 2) AS avg_salary_from, -- средняя зарплата в категории «от»
       ROUND(AVG(salary_to), 2) AS avg_salary_to,     -- средняя зарплата в категории «до»
       MIN(salary_from) AS min_salary_from,           -- минимальная зарплата в категории «от»
       MAX(salary_from) AS max_salary_from,           -- максимальная зарплата в категории «от»
       MIN(salary_to) AS min_salary_to,               -- минимальная зарплата в категории «до»
       MAX(salary_to) AS max_salary_to                -- максимальная зарплата в категории «до»
FROM public.parcing_table;
-- avg_salary_from|avg_salary_to|min_salary_from|max_salary_from|min_salary_to|max_salary_to|
-- ---------------+-------------+---------------+---------------+-------------+-------------+
--       109525.09|    153846.71|           50.0|       398000.0|      25000.0|     497500.0|
-- Средние границы зарплаты для аналитиков: от 109 525 до 153 847 руб. (по вакансиям, где зарплата указана).
-- Минимальная зарплата «от» в 50 руб., скорее всего, ошибка ввода, а максимальная граница достигает 497 500 руб.

-- 2 ТОП-5 РЕГОНОВ ПО КОЛИЧЕСВУ ВАКАНСИЙ 
SELECT area,
       COUNT(*) AS area_vacancies
FROM public.parcing_table
GROUP BY area
ORDER BY area_vacancies DESC
LIMIT 5;
-- area           |area_vacancies|
-- ---------------+--------------+
-- Москва         |          1247|
-- Санкт-Петербург|           181|
-- Екатеринбург   |            51|
-- Нижний Новгород|            33|
-- Новосибирск    |            33|
-- Москва (около 69% вакансий) и Санкт-Петербург (около 10%) — безусловные лидеры по числу вакансий.
-- Рынок труда для аналитиков данных сосредоточен в двух столицах.

-- 3 ТОП-5 КОМПАНИЙ ПО КОЛИЧЕСВУ ВАКАНСИЙ 
SELECT employer,
       COUNT(*) AS employer_vacancies
FROM public.parcing_table
GROUP BY employer
ORDER BY employer_vacancies DESC
LIMIT 5;
-- employer      |employer_vacancies|
-- --------------+------------------+
-- СБЕР          |               243|
-- WILDBERRIES   |                43|
-- Ozon          |                34|
-- Банк ВТБ (ПАО)|                28|
-- Т1            |                26|
-- СБЕР предлагает 243 вакансии (около 13%) и является крупнейшим работодателем для аналитиков.
-- Среди лидеров также банки и маркетплейсы, то есть много вакансий в финансовой сфере и e-commerce.

-- 4 KОЛИЧЕСВО ВАКАНСИЙ ПО ТИПАМ ЗАНЯТОСТИ 
SELECT employment,
       COUNT(*) AS num_vacancies
FROM public.parcing_table
GROUP BY employment
ORDER BY num_vacancies DESC;
-- employment         |num_vacancies|
-- -------------------+-------------+
-- Полная занятость   |         1764|
-- Частичная занятость|           16|
-- Стажировка         |           16|
-- Проектная работа   |            5|
-- На рынке преобладает полная занятость (около 98% вакансий), стажировок и проектной работы очень мало.
-- Возможно, это связано с необходимостью глубоко погружаться в проекты и долго в них участвовать.

-- 5 КОЛИЧЕСТВО ВАКАНСИЙ ПО ГРАФИКУ РАБОТЫ 
SELECT schedule,
       COUNT(*) AS num_vacancies
FROM public.parcing_table
GROUP BY schedule
ORDER BY num_vacancies DESC;
-- schedule        |num_vacancies|
-- ----------------+-------------+
-- Полный день     |         1441|
-- Удаленная работа|          310|
-- Гибкий график   |           41|
-- Сменный график  |            9|
-- Большинство вакансий (1 441, или 80%) предлагают работу полный день.
-- Значительная часть (310, или 17%) допускает удалённую работу, а значит, работодатели готовы быть гибкими.

-- 6 ВОСТРЕБОВАННОСТЬ ГРЕЙДОВ 
SELECT experience,
       COUNT(*) AS experience_vacancies,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM public.parcing_table
GROUP BY experience
ORDER BY experience_vacancies DESC;
-- experience           |experience_vacancies|percentage|
-- ---------------------+--------------------+----------+
-- Junior+ (1-3 years)  |                1091|     60.58|
-- Middle (3-6 years)   |                 555|     30.82|
-- Junior (no experince)|                 142|      7.88|
-- Senior (6+ years)    |                  13|      0.72|
-- Больше всего вакансий для специалистов с опытом 1–3 года (60,6%), а вакансий для Middle в два раза меньше, но их тоже много.
-- Спрос на Senior крайне низкий (0,7%), возможно, из-за узкого круга таких специалистов; для них, вероятно, чаще используются другие каналы поиска.

-- 7 НАИБОЛЕЕЧАСТЫЕ HARD И SOFT НАВЫКИ 

-- 7.1 Наиболее частые hard и soft навыки по позициям в списке требований
-- Разворачиваем столбцы с навыками в одну таблицу, сохраняя номер столбца, и убираем пустые значения
WITH all_skills AS (
    SELECT 'key_skills_1' AS column_name,
           key_skills_1 AS skill
    FROM public.parcing_table
    WHERE key_skills_1 IS NOT NULL AND key_skills_1 <> ''
    UNION ALL
    SELECT 'key_skills_2', key_skills_2
    FROM public.parcing_table
    WHERE key_skills_2 IS NOT NULL AND key_skills_2 <> ''
    UNION ALL
    SELECT 'key_skills_3', key_skills_3
    FROM public.parcing_table
    WHERE key_skills_3 IS NOT NULL AND key_skills_3 <> ''
    UNION ALL
    SELECT 'key_skills_4', key_skills_4
    FROM public.parcing_table
    WHERE key_skills_4 IS NOT NULL AND key_skills_4 <> ''
    UNION ALL
    SELECT 'soft_skills_1', soft_skills_1
    FROM public.parcing_table
    WHERE soft_skills_1 IS NOT NULL AND soft_skills_1 <> ''
    UNION ALL
    SELECT 'soft_skills_2', soft_skills_2
    FROM public.parcing_table
    WHERE soft_skills_2 IS NOT NULL AND soft_skills_2 <> ''
    UNION ALL
    SELECT 'soft_skills_3', soft_skills_3
    FROM public.parcing_table
    WHERE soft_skills_3 IS NOT NULL AND soft_skills_3 <> ''
    UNION ALL
    SELECT 'soft_skills_4', soft_skills_4
    FROM public.parcing_table
    WHERE soft_skills_4 IS NOT NULL AND soft_skills_4 <> ''
), -- таблица из номера столбца и навыка
skill_counts AS (
    SELECT column_name,
           skill,
           COUNT(*) AS skill_count,
           ROW_NUMBER() OVER (PARTITION BY column_name ORDER BY COUNT(*) DESC) AS rang
    FROM all_skills
    GROUP BY column_name, skill
) -- считаем упоминания и присваиваем рейтинг внутри каждого столбца
SELECT column_name,
       skill,
       skill_count
FROM skill_counts
WHERE rang <= 1
ORDER BY column_name, skill_count DESC;
-- column_name  |skill                  |skill_count|
-- -------------+-----------------------+-----------+
-- key_skills_1 |Анализ данных          |        312|
-- key_skills_2 |SQL                    |        318|
-- key_skills_3 |SQL                    |        220|
-- key_skills_4 |Python                 |        113|
-- soft_skills_1|Документация           |        234|
-- soft_skills_2|Документация           |         46|
-- soft_skills_3|Аналитическое мышление |          9|
-- soft_skills_4|Внимание к деталям     |          3|
-- Число упоминаний убывает от первого столбца к последнему, потому что самые важные навыки обычно указывают первыми.
-- SQL лидирует среди hard skills на второй и третьей позициях, а «Документация» — среди soft skills на первых двух.

-- 7.2 Наиболее частые hard и soft навыки в целом
-- Объединяем позиции в две группы (hard и soft) и очищаем значения от пробелов в начале
WITH all_key_skills AS (
    SELECT 'key_skills' AS column_name,
           TRIM(key_skills_1) AS skill
    FROM public.parcing_table
    WHERE key_skills_1 IS NOT NULL AND TRIM(key_skills_1) <> ''
    UNION ALL
    SELECT 'key_skills', TRIM(key_skills_2)
    FROM public.parcing_table
    WHERE key_skills_2 IS NOT NULL AND TRIM(key_skills_2) <> ''
    UNION ALL
    SELECT 'key_skills', TRIM(key_skills_3)
    FROM public.parcing_table
    WHERE key_skills_3 IS NOT NULL AND TRIM(key_skills_3) <> ''
    UNION ALL
    SELECT 'key_skills', TRIM(key_skills_4)
    FROM public.parcing_table
    WHERE key_skills_4 IS NOT NULL AND TRIM(key_skills_4) <> ''
    UNION ALL
    SELECT 'soft_skills', TRIM(soft_skills_1)
    FROM public.parcing_table
    WHERE soft_skills_1 IS NOT NULL AND TRIM(soft_skills_1) <> ''
    UNION ALL
    SELECT 'soft_skills', TRIM(soft_skills_2)
    FROM public.parcing_table
    WHERE soft_skills_2 IS NOT NULL AND TRIM(soft_skills_2) <> ''
    UNION ALL
    SELECT 'soft_skills', TRIM(soft_skills_3)
    FROM public.parcing_table
    WHERE soft_skills_3 IS NOT NULL AND TRIM(soft_skills_3) <> ''
    UNION ALL
    SELECT 'soft_skills', TRIM(soft_skills_4)
    FROM public.parcing_table
    WHERE soft_skills_4 IS NOT NULL AND TRIM(soft_skills_4) <> ''
), -- таблица из группы навыка и самого навыка
skill_counts AS (
    SELECT column_name,
           skill,
           COUNT(*) AS skill_count,
           ROW_NUMBER() OVER (PARTITION BY column_name ORDER BY COUNT(*) DESC) AS rang
    FROM all_key_skills
    GROUP BY column_name, skill
) -- считаем упоминания и присваиваем рейтинг внутри каждой группы
SELECT column_name,
       skill,
       skill_count
FROM skill_counts
WHERE rang <= 3
ORDER BY column_name, skill_count DESC;
-- Среди hard skills лидируют SQL, Python и анализ данных, то есть SQL и Python — базовый набор для аналитика.
-- Среди soft skills на первом месте «Документация»: работодатели ценят умение вести и оформлять документацию не меньше коммуникативных качеств.




-- ОБЩИЙ ВЫВОД ПО АНАЛИЗУ

-- Данные. В выборке 1 801 вакансия аналитиков данных за период с 13 февраля по 11 июня 2024 года, все названия относятся к аналитике.
-- Аномалии: минимальная зарплата «от» в 50 руб. (ошибка ввода), пропуски в зарплате и навыках, пробелы в начале значений soft skills.
-- География. Рынок сосредоточен в Москве (около 69% вакансий) и Санкт-Петербурге (около 10%), далее идут Екатеринбург, Нижний Новгород и Новосибирск.
-- Работодатели. Крупнейший — СБЕР (243 вакансии, около 13%), далее Wildberries, Ozon, ВТБ и Т1: спрос создают банки и маркетплейсы.
-- Условия. Преобладает полная занятость (около 98%) и полный рабочий день (80%), при этом 17% вакансий допускают удалённую работу.
-- Грейды. Основной спрос на специалистов с опытом 1–3 года (60,6%) и 3–6 лет (30,8%); вакансий без опыта около 8%, для Senior — менее 1%.
-- Зарплата. Средние границы предложений составляют от 109 525 до 153 847 руб. (по вакансиям с указанной зарплатой).
-- Навыки. Самые востребованные hard skills — SQL, Python и анализ данных, среди soft skills лидирует ведение документации.
-- Рекомендации. Начинающему аналитику стоит сосредоточиться на SQL и Python, ориентироваться на позиции Junior+ и рассматривать вакансии в Москве и Санкт-Петербурге, а также удалённые.