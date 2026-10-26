-- ============================================================
-- Домашнее задание к лекции «SQL»
-- Школа Аналитиков · учебная база hh_school
-- Автор: [Лобачёв Андрей Александрович]
-- ============================================================
-- Формат: задания по порядку, каждое начинается с комментария
-- с номером; под каждым запросом - вывод.
-- Запрос без вывода не засчитывается.
-- ============================================================

SET search_path TO hh_school;


-- ============================================================
-- БЛОК А. Качество и подготовка данных
-- ============================================================

-- 1. АУДИТ КАЧЕСТВА ДАННЫХ
-- * Проверяем, можно ли корректно связать событие с откликом;

-- Запрос 1:
    SELECT count(*) AS cnt_null_response_id
    FROM messages
    WHERE response_id IS NULL;

-- Вывод: Проверка таблицы messages показала 0 строк с отсутствующим response_id. Все сообщения правильно привязаны к откликам.

-- Запрос 2: 
    SELECT count(*) AS cnt_null_response_id
    FROM calls
    WHERE response_id IS NULL;

-- Вывод: Проверка таблицы calls показала 8 строк с отсутствующим response_id. Вот и первый недочёт, здесь связь нарушается.


-- * Проверяем, согласуются ли между собой идентификаторы в связанных таблицах;

-- Запрос 1:
    SELECT count(*) AS mismatched_vacancy_messages
    FROM messages m
    JOIN responses r 
        ON m.response_id = r.response_id
    WHERE m.vacancy_id != r.vacancy_id;

-- Запрос 2:
    SELECT count(*) AS mismatched_vacancy_calls
    FROM calls c
    JOIN responses r 
        ON c.response_id = r.response_id
    WHERE c.vacancy_id != r.vacancy_id;

-- Вывод: Результат - 0 строк для обеих таблиц. Значит, все идентификаторы согласованы. vacancy_id в таблицах звонков и сообщений полностью соответствуют vacancy_id в откликах.


-- * Проверяем, может ли событие находиться в указанной точке времени относительно отклика;
-- Работодатель физически не может позвонить или написать кандидату по отклику до того, как этот отклик был отправлен, поэтому call_at и sent_at должны быть строго больше created_at у response.

-- Запрос 1:
    SELECT count(*) AS time_messages
    FROM messages m
    JOIN responses r 
        ON m.response_id = r.response_id
    WHERE m.sent_at < r.created_at;

-- Запрос 2:
    SET search_path = hh_school;
    SELECT count(*) AS time_calls
    FROM calls c
    JOIN responses r 
        ON c.response_id = r.response_id
    WHERE c.call_at < r.created_at;

-- Вывод: ни одной строки, где работодатель позвонил бы или написал раньше отклика. Здесь тоже всё ок! 


-- * Проверяем, согласуются ли значения внутри одной строки между собой;
-- В контексте задания не может быть так, чтобы звонок был пропущен и его длительность была > 0; верна и обратная ситуация, если звонок успешный, то его длительность не может быть равна 0 (<0 не проверяю, так как сделал отдельный запрос с SELECT DISTINCT call_duration, отрицательных значений нет).
-- Оговорка про messages: часть данных лежат в message_meta формата JSON. Не уверен, что JSON надо затрагивать уже в первом пункте, так как под него отведён Блок Г (Сложные типы данных). Оставлю это на потом, разберёмся чуть позже :)

-- Запрос 1:
    SET search_path = hh_school;
    SELECT count(*) AS invalid_missed_calls
    FROM calls
    WHERE status IN ('unsuccessful', 'error') AND call_duration > 0;
                   
-- Запрос 2:
    SET search_path = hh_school;
    SELECT count(*) AS invalid_successful_calls
    FROM calls
    WHERE status = 'successful' AND (call_duration IS NULL OR call_duration = 0);

-- Вывод: здесь ошибок тоже нет, в результате получается ноль. 

-- * Проверяем, есть ли пропуски в данных, которые понадобятся дальше;

-- Запрос 1: 
    SELECT count(*) AS null_critical_messages
    FROM messages
    WHERE employer_id IS NULL OR vacancy_id IS NULL OR sent_at IS NULL;

-- Запрос 2: 
    SELECT count(*) AS null_critical_calls
    FROM calls
    WHERE employer_id IS NULL OR vacancy_id IS NULL OR call_at IS NULL;

-- Вывод: 
-- Пропусков в нужных нам полях (employer_id, vacancy_id, sent_at / call_at) нет (найдено 0 строк). 
-- Это ожидаемо, потому что в схеме БД на dbdiagram можно заметить, что справа у этих колонок стоит ограничение NOT NULL. Доверяй, но проверяй!


-- * Проверяем, есть ли значения, заметно отличающиеся от основной массы наблюдений (считаем 5 метрик на call_duration);

-- Запрос c CTE:
    WITH call_stats AS ( 
        SELECT 
            AVG(call_duration) AS avg_all,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY call_duration) AS median_val,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration) AS p99_val
        FROM calls
        WHERE status = 'successful'
    )

    SELECT 
        ROUND(s.avg_all) AS avg_duration,
        s.median_val AS median_duration,
        s.p99_val AS p99_duration,
        COUNT(c.call_id) FILTER (WHERE c.call_duration > s.p99_val) AS count_above_p99,
        ROUND(AVG(c.call_duration) FILTER (WHERE c.call_duration <= s.p99_val)) AS avg_duration_filtered
    FROM calls c
    CROSS JOIN call_stats s
    WHERE c.status = 'successful'
    GROUP BY 1, 2, 3;

-- Вывод по поиску выбросов:
-- Заметно отличающиеся значения есть: это 2 успешных звонка, длительность которых превышает 99-й перцентиль (890.4 секунды, или примерно 15 минут).
-- Я считаю эти значения допустимыми бизнес-выбросами, а не техническими ошибками. В сфере найма первичное телефонное интервью с кандидатом вполне может длиться дольше 15 минут.
-- Эти записи не требуют удаления. Их исключение практически не влияет на общую картину (очищенная средняя длительность падает всего на 5 секунд: с 467 до 462). Для оценки "базового" звонка в дальнейшем безопаснее использовать медиану (438 секунд).

-- ============================================================
-- ИТОГОВЫЙ ВЫВОД ПО ПРОБЛЕМНЫМ ЗАПИСЯМ
-- ============================================================

-- Запрос для вывода конкретных проблемных записей:
    SELECT call_id
    FROM calls
    WHERE response_id IS NULL;

-- Итог по проблемам:
-- 1. Количество строк: 8.
-- 2. Проблемные записи: 700244, 700245, 700246, 700247, 700248, 700249, 700250, 700251.
-- 3. Эта проблема влияет на сам факт коммуникации. Из-за отсутствия response_id эти звонки нельзя привязать к конкретному кандидату и отклику, поэтому они полностью исключаются из дальнейшего построения таймлайна.



-- ============================================================
-- БЛОК Б. История коммуникаций
-- ============================================================

-- 2. ЕДИНЫЙ СЛОЙ КОММУНИКАЦИЙ  
-- Запрос:
    WITH event_messages AS (
        SELECT 
            m.response_id,
            m.employer_id, 
            m.message_id AS event_id,
            m.sent_at AS event_at,
            'message' AS event_type
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sent_at <= r.created_at + INTERVAL '7 days'
        
    ),
    event_calls AS (
        SELECT
            c.response_id,
            c.employer_id, 
            c.call_id AS event_id,
            c.call_at AS event_at,
            'call' AS event_type
        FROM calls c
        INNER JOIN responses r ON c.response_id = r.response_id
        WHERE c.call_at <= r.created_at + INTERVAL '7 days'
    ),
    events AS (
        SELECT * FROM event_messages
        UNION ALL
        SELECT * FROM event_calls
    )

    SELECT
        count(*) AS count_events,
        count(DISTINCT response_id) AS count_unique_responses,
        count(event_type) FILTER (WHERE event_type = 'call') AS count_calls,
        count(event_type) FILTER (WHERE event_type = 'message') AS count_messages
    FROM events;

-- Вывод по единому слою коммуникаций за первые 7 дней:
-- 1) Общее количество событий: 2144
-- 2) Количество различных откликов с коммуникацией: 398
-- 3) Количество звонков: 168
-- 4) Количество сообщений: 1976

-- Комментарий: 
-- Можно заметить, что сообщения отправляются преимущественно чаще, чем совершаются звонки - это абсолютно логично, так как первичная связь от HR идёт в чате, где потом уже обсуждается время для разговорного интервью.
-- INNER JOIN не включает NULL-значения, поэтому те проблемные 8 звонков отсеклись без строгих заданных условий.

-- 3. ТАЙМЛАЙН КОММУНИКАЦИЙ И ВИТРИНА ОТКЛИКА
-- ШАГ 1: Слой уровня события
-- Запрос:

    SELECT 
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type,
        
        ROW_NUMBER() OVER w AS event_number,
        
        LAG(event_at) OVER w AS prev_event_time,
        
        LEAD(event_type) OVER w AS next_event_type,
        
        COUNT(event_id) OVER w AS count_events_to_date,
        
        FIRST_VALUE(event_type) OVER w AS first_event_type,

        LAST_VALUE(event_type) OVER (
            PARTITION BY response_id 
            ORDER BY event_at, event_type, event_id 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type

FROM events
WINDOW w AS (PARTITION BY response_id ORDER BY event_at, event_type, event_id);

-- Вывод:
-- Теперь каждая коммуникация имеет свой контекст: её порядковый номер, что было до и после неё, а также с чего началось и чем закончилось общение по конкретному отклику. 
-- Слой готов к агрегации - на его основе можно легко вычислить временные интервалы и статусы для итоговой витрины откликов на следующем шаге.

-- ШАГ 2: Витрина уровня отклика
-- Запрос: 

    WITH event_messages AS (
        SELECT 
            m.response_id,
            m.employer_id,
            m.message_id AS event_id,
            m.sent_at AS event_at,
            'message' AS event_type
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sent_at <= r.created_at + INTERVAL '7 days'
    ),
    event_calls AS (
        SELECT 
            c.response_id,
            c.employer_id,
            c.call_id AS event_id,
            c.call_at AS event_at,
            'call' AS event_type
        FROM calls c
        INNER JOIN responses r ON c.response_id = r.response_id
        WHERE c.call_at <= r.created_at + INTERVAL '7 days'
    ),
    events AS (
        SELECT * FROM event_messages
        UNION ALL
        SELECT * FROM event_calls
    ),
    timeline AS (
        SELECT 
            response_id,
            employer_id,
            event_id,
            event_at,
            event_type,
            ROW_NUMBER() OVER w AS event_number,
            LAG(event_at) OVER w AS prev_event_time,
            LEAD(event_type) OVER w AS next_event_type,
            COUNT(event_id) OVER w AS count_events_to_date,
            FIRST_VALUE(event_type) OVER w AS first_event_type,
            LAST_VALUE(event_type) OVER (
                PARTITION BY response_id 
                ORDER BY event_at, event_type, event_id 
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS last_event_type
        FROM events
        WINDOW w AS (PARTITION BY response_id ORDER BY event_at, event_type, event_id)
    ),
    response_datamart AS (
        SELECT 
            r.response_id,
            v.employer_id,
            v.professional_role,
            r.status AS response_status,
            COUNT(t.event_id) AS count_events,
            COUNT(t.event_id) FILTER (WHERE t.event_type = 'call') AS count_calls,
            COUNT(t.event_id) FILTER (WHERE t.event_type = 'message') AS count_messages,
            MIN(t.event_at) AS first_event_time,
            MAX(t.first_event_type) AS first_event_type,
            MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_event_type,
            MAX(t.last_event_type) AS last_event_type,
            MIN(t.event_at) - r.created_at AS time_to_first_comm,
            MAX(t.event_at - t.prev_event_time) AS max_interval
        FROM responses r
        INNER JOIN vacancies v ON r.vacancy_id = v.vacancy_id
        LEFT JOIN timeline t ON r.response_id = t.response_id
        GROUP BY 
            r.response_id,
            v.employer_id,
            v.professional_role,
            r.status,
            r.created_at
    )
    SELECT 
        COUNT(*) AS count_total_rows,
        COUNT(*) FILTER (WHERE count_events > 0) AS count_with_comm,
        COUNT(*) FILTER (WHERE count_events = 0) AS count_without_comm,
        COUNT(*) FILTER (WHERE first_event_type = 'message') AS count_first_message,
        COUNT(*) FILTER (WHERE first_event_type = 'call') AS count_first_call
    FROM response_datamart;

-- Вывод:
-- 1. Общее количество строк (откликов) в витрине: 628
-- 2. Количество откликов с коммуникацией: 398
-- 3. Количество откликов без коммуникации: 230
-- 4. Количество откликов, где первой коммуникацией было сообщение: 303
-- 5. Количество откликов, где первой коммуникацией был звонок: 95
-- Статистика первых коммуникаций (303 сообщения против 95 звонков) подтверждает гипотезу из предыдущего блока: HR в подавляющем большинстве случаев предпочитают начинать коммуникацию с кандидатом через чат (в примерно 76% случаев).



-- ============================================================
-- БЛОК В. Сравнение работодателей
-- ============================================================

-- 4. РЕЙТИНГ РАБОТОДАТЕЛЕЙ ВНУТРИ НАПРАВЛЕНИЯ
-- Запрос:
    WITH event_messages AS (
        SELECT 
            m.response_id,
            m.employer_id,
            m.message_id AS event_id,
            m.sent_at AS event_at,
            'message' AS event_type
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sent_at <= r.created_at + INTERVAL '7 days'
    ),
    event_calls AS (
        SELECT 
            c.response_id,
            c.employer_id,
            c.call_id AS event_id,
            c.call_at AS event_at,
            'call' AS event_type
        FROM calls c
        INNER JOIN responses r ON c.response_id = r.response_id
        WHERE c.call_at <= r.created_at + INTERVAL '7 days'
    ),
    events AS (
        SELECT * FROM event_messages
        UNION ALL
        SELECT * FROM event_calls
    ),
    timeline AS (
        SELECT 
            response_id,
            employer_id,
            event_id,
            event_at,
            event_type,
            ROW_NUMBER() OVER w AS event_number,
            LAG(event_at) OVER w AS prev_event_time,
            LEAD(event_type) OVER w AS next_event_type,
            COUNT(event_id) OVER w AS count_events_to_date,
            FIRST_VALUE(event_type) OVER w AS first_event_type,
            LAST_VALUE(event_type) OVER (
                PARTITION BY response_id 
                ORDER BY event_at, event_type, event_id 
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS last_event_type
        FROM events
        WINDOW w AS (PARTITION BY response_id ORDER BY event_at, event_type, event_id)
    ),
    response_datamart AS (
        SELECT 
            r.response_id,
            v.employer_id,
            v.professional_role,
            r.status AS response_status,
            COUNT(t.event_id) AS count_events,
            COUNT(t.event_id) FILTER (WHERE t.event_type = 'call') AS count_calls,
            COUNT(t.event_id) FILTER (WHERE t.event_type = 'message') AS count_messages,
            MIN(t.event_at) AS first_event_time,
            MAX(t.first_event_type) AS first_event_type,
            MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_event_type,
            MAX(t.last_event_type) AS last_event_type,
            MIN(t.event_at) - r.created_at AS time_to_first_comm,
            MAX(t.event_at - t.prev_event_time) AS max_interval
        FROM responses r
        INNER JOIN vacancies v ON r.vacancy_id = v.vacancy_id
        LEFT JOIN timeline t ON r.response_id = t.response_id
        GROUP BY 
            r.response_id,
            v.employer_id,
            v.professional_role,
            r.status,
            r.created_at
    ),
    employer_stats AS (
        SELECT 
            professional_role,
            employer_id,
            COUNT(*) AS total_responses,
            COUNT(*) FILTER (WHERE count_events > 0) AS count_with_comm,
            ROUND(COUNT(*) FILTER (WHERE count_events > 0) * 100.0 / COUNT(*), 2) AS processed_percentage,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY time_to_first_comm) AS median_time,
            PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY time_to_first_comm) AS p90_time,
            ROUND(COUNT(*) FILTER (WHERE response_status = 'invitation') * 100.0 / COUNT(*), 2) AS invitation_conversion
        FROM response_datamart
        GROUP BY professional_role, employer_id
    ),
    ranked_employers AS (
        SELECT 
            professional_role,
            employer_id,
            DENSE_RANK() OVER (
                PARTITION BY professional_role 
                ORDER BY processed_percentage DESC, median_time ASC
            ) AS place
        FROM employer_stats
        WHERE total_responses >= 8
    )
    SELECT 
        professional_role,
        place,
        employer_id
    FROM ranked_employers
    WHERE place <= 2
    ORDER BY professional_role, place, employer_id;

-- Вывод:
-- Аналитик данных: 1 место - 109, 2 место - 103
-- Дата-инженер: 1 место - 106, 2 место - 101
-- Продуктовый аналитик: 1 место - 103, 2 место - 102
-- Разработчик: 1 место - 112, 2 место - 104
-- Тестировщик: 1 место - 107, 2 место - 108
-- Стоит отметить работодателя 103, который вошел в топ сразу по двум смежным направлениям («Аналитик данных» и «Продуктовый аналитик»). Это явный показатель того, что у компании выстроен процесс найма data-специалистов, а рекрутёры работают с этими кандидатами максимально оперативно.

-- 5. СКОРОСТЬ ОТВЕТА РАБОТОДАТЕЛЯ В ПЕРЕПИСКЕ
-- Запрос:
    WITH valid_messages AS (
        SELECT 
            m.response_id,
            m.employer_id,
            m.message_id,
            m.sender_role,
            m.sent_at
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sent_at <= r.created_at + INTERVAL '7 days'
    ),
    message_timeline AS (
        SELECT 
            response_id,
            employer_id,
            sender_role,
            sent_at,
            LAG(sender_role) OVER w AS prev_sender_role,
            LAG(sent_at) OVER w AS prev_sent_at
        FROM valid_messages
        WINDOW w AS (PARTITION BY response_id ORDER BY sent_at, message_id)
    ),
    employer_responses AS (
        SELECT 
            employer_id,
            sent_at - prev_sent_at AS response_time
        FROM message_timeline
        WHERE sender_role = 'employer' 
        AND prev_sender_role = 'applicant'
    )
    SELECT 
        employer_id,
        COUNT(*) AS responses_count,
        AVG(response_time) AS avg_response_time,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY response_time) AS median_response_time,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY response_time) AS p90_response_time
    FROM employer_responses
    GROUP BY employer_id
    ORDER BY median_response_time ASC;

-- Аналитический комментарий:
-- Работодатель 107 формально лидирует (медиана ответа 03:56:00), однако его среднее время ответа составляет более 9 часов (09:22:27). Такой разрыв между медианой и средним указывает на сильные выбросы - часть кандидатов ждет ответа очень долго (90-й перцентиль почти 20 часов). 
-- На самом деле отличный результат показывают работодатели 103 и 101: они обрабатывают огромный объём ответов (171 и 161 соответственно), при этом удерживают медиану на стабильном уровне около 4,5 часов. Это признак системно отработанного процесса найма.



-- ============================================================
-- БЛОК Г. Сложные типы данных
-- ============================================================

-- 6. СЛОЖНЫЕ ТИПЫ ДАННЫХ

-- 6.1 ТЕГИ ЗВОНКОВ

-- Проверка 1: ищем звонки, у которых status противоречит техническим тегам.
-- Запрос 1:
    SELECT COUNT(*) AS invalid_calls
    FROM calls
    WHERE
        (status IN ('unsuccessful', 'error') AND 'connected' = ANY(call_tags))
        OR
        (status = 'successful' AND 'no_answer' = ANY(call_tags));

-- Вывело ноль несогласованных звонков. Тут всё в порядке.


-- Проверка 2: ищем звонки, у которых нет ни connected, ни no_answer.
-- Запрос 2: 
    SELECT
        call_id,
        status,
        call_tags
    FROM calls
    WHERE NOT ('connected' = ANY(call_tags))
        AND NOT ('no_answer' = ANY(call_tags));

-- Этот запрос вывел status 'error', но в call_tag у него 'technical_error', так что здесь тоже всё согласовано, это допустимо.


-- Проверка 3: ищем звонки, у которых одновременно есть connected и no_answer.
-- Запрос 3:
    SELECT
        call_id,
        status,
        call_tags
    FROM calls
    WHERE 'connected' = ANY(call_tags)
        AND 'no_answer' = ANY(call_tags);

-- Таких звонков тоже нет.
-- Вывод: 
-- Предположения не подтвердились, и это супер. Явных противоречий между статусами звонков и их call_tags нет.
-- Следовательно, по этим критериям исключать в итоговом запросе звонки не требуется. 

-- Финальный запрос: 
    SELECT 
        COUNT(*) FILTER (WHERE 'screening' = ANY(c.call_tags)) AS count_screenings,
        COUNT(*) FILTER (WHERE 'interview' = ANY(c.call_tags)) AS count_interviews,
        COUNT(*) FILTER (WHERE 'follow_up' = ANY(c.call_tags)) AS count_followups,
        COUNT(*) FILTER (WHERE 'details' = ANY(c.call_tags)) AS count_details,
        COUNT(*) FILTER (WHERE 'screening' = ANY(c.call_tags) OR 'interview' = ANY(c.call_tags) OR 'follow_up' = ANY(c.call_tags) OR 'details' = ANY(c.call_tags)) AS count_valid_calls,
        AVG(CARDINALITY(c.call_tags)) AS avg_tags_per_call
    FROM calls c
    INNER JOIN responses r ON c.response_id = r.response_id
    WHERE (c.caller_role = 'employer') AND c.call_at <= r.created_at + INTERVAL '7 days' AND c.call_at >= r.created_at;

-- Вывод: 
-- Добавил нижнюю границу c.call_at >= r.created_at по правилам хорошего тона, хотя ещё в блоке А проверил, что звонков раньше отклика нет.

-- 1) count_screenings: 25
-- 2) count_interviews: 31 
-- 3) сount_followups: 29
-- 4) count_details: 23
-- 5) count_valid_calls: 108
-- 6) avg_tags_per_call: 4

-- Здесь через CARDINALITY считаются все элементы массива, включая технические теги voice, connected, outbound и другие. Поэтому стоит отметить, что результат нельзя интерпретировать как среднее количество именно бизнес-тегов на звонок.


-- 6.2. МЕТАДАННЫЕ СООБЩЕНИЙ

-- Сначала исследуем структуру attachments. Первоначально предположил, что attachments хранит количество вложений как integer, но получил ошибку преобразования значения [] в число. Оказалось, что внутри JSONB хранится массив вложений, поэтому используем JSONB_ARRAY_LENGTH.
-- Запрос 1:
    SELECT
        JSONB_TYPEOF(message_meta -> 'attachments') AS attachments_type,
        COUNT(*) AS count_messages
    FROM messages
    GROUP BY 1;

-- Вывод:
-- Все 2862 сообщения содержат attachments типа array, поэтому для подсчёта вложений используем JSONB_ARRAY_LENGTH, а не ::integer.

-- Запрос 2:
    SELECT
        COALESCE(message_meta ->> 'channel', 'unknown') AS channel,
        COUNT(*) AS count_messages,
        COUNT(*) FILTER (WHERE NOT (message_meta ? 'is_read')) AS missing_is_read,
        COUNT(*) FILTER (WHERE message_meta ->> 'is_read' IS NULL) AS unknown_is_read,
        COUNT(*) FILTER (WHERE NOT (message_meta ? 'attachments')) AS missing_attachments
    FROM messages
    GROUP BY 1
    ORDER BY count_messages DESC;

-- Вывод:
-- Всего в таблице 2862 сообщения: 1866 через web и 996 через mobile_app.
-- Пропусков в is_read и attachments не обнаружено, channel тоже указан везде.
-- На текущих данных группа unknown не появилась, но считаю правильным оставить COALESCE, чтобы сообщения без канала не потерялись при возможном появлении пропусков.



-- Запрос 3:
    SELECT
        COUNT(*) AS total_messages,
        COUNT(DISTINCT m.response_id) AS unique_responses,
        COUNT(*) FILTER (WHERE m.message_meta ->> 'is_read' IS NOT NULL) AS known_read,
        COUNT(*) FILTER (WHERE m.message_meta ->> 'is_read' = 'false') AS unread_messages,
        COUNT(*) FILTER (
            WHERE JSONB_ARRAY_LENGTH(m.message_meta -> 'attachments') > 0
        ) AS messages_with_attachments
    FROM messages m
    INNER JOIN responses r
        ON m.response_id = r.response_id
    WHERE m.sender_role = 'employer'
        AND m.sent_at >= r.created_at
        AND m.sent_at < r.created_at + INTERVAL '7 days';

-- Вывод:
-- В исследуемый период попало 988 сообщений работодателя по 344 различным откликам.
-- У всех 988 сообщений известен признак прочтения.
-- Непрочитанными остались 88 сообщений (прочитаны остальные 900), вложения содержат 39 сообщений.

-- Итоговый запрос:
    WITH valid_messages AS (
        SELECT
            m.message_id,
            m.response_id,
            m.message_meta ->> 'channel' AS channel,
            (m.message_meta ->> 'is_read')::boolean AS is_read,
            JSONB_ARRAY_LENGTH(m.message_meta -> 'attachments') AS attachments_count
        FROM messages m
        INNER JOIN responses r
            ON m.response_id = r.response_id
        WHERE m.sender_role = 'employer'
            AND m.sent_at >= r.created_at
            AND m.sent_at < r.created_at + INTERVAL '7 days'
    )

    SELECT
        COALESCE(channel, 'unknown') AS channel,
        COUNT(*) AS count_messages,
        COUNT(is_read) AS count_known_read,
        COUNT(*) FILTER (WHERE is_read = false) AS count_unread,
        ROUND(
            COUNT(*) FILTER (WHERE is_read = false) * 100.0
            / NULLIF(COUNT(is_read), 0), 2
        ) AS unread_percentage,
        COUNT(*) FILTER (WHERE attachments_count > 0) AS count_with_attachments,
        ROUND(
            COUNT(*) FILTER (WHERE attachments_count > 0) * 100.0
            / NULLIF(COUNT(*), 0), 2
        ) AS attachments_percentage
    FROM valid_messages
    GROUP BY COALESCE(channel, 'unknown')
    ORDER BY count_messages DESC;


-- Итоговый вывод по метаданным сообщений:

-- 1) Самый популярный канал общения работодателей с кандидатами - web. Через него отправлено 628 сообщений, а через mobile_app 360. То есть около 64% исследуемых сообщений приходится на web.

-- 2) Доля непрочитанных сообщений в web составляет 8.28%, в mobile_app - 10%.
-- Разница составляет 1.72 процентного пункта.
-- Можно предположить, что сообщения через web читают немного чаще, но по этим данным нельзя утверждать, что сам канал является причиной.
-- На прочтение могут влиять особенности кандидатов, время отправки и другие факторы.

-- 3) Вложения встречаются довольно редко: всего 39 сообщений из 988. В web их 25, в mobile_app - 14.
-- Доля сообщений с вложениями в web составляет 3.98%, а в mobile_app - 3.89%.
-- Разница между каналами минимальна, поэтому делать вывод о существенных различиях в использовании вложений не стоит.

-- 4) Важно, что долю непрочитанных считаю здесь только среди сообщений, для которых известен is_read. NULL и false - не одно и то же: отсутствие признака прочтения не означает, что сообщение не прочитали.

-- 5) Для web признак прочтения известен у всех 628 сообщений, из которых 52 непрочитанных. Для mobile_app признак прочтения также известен у всех 360 сообщений, из которых 36 непрочитанных. 88 сообщений из 988 остались непрочитанными.



-- ============================================================
-- БЛОК Д. Самостоятельное исследование
-- ============================================================

-- 7. ЧТО СВЯЗАНО С ПРИГЛАШЕНИЕМ?
-- Выдвигаю следующие гипотезы:

-- Гипотеза 1. Скорость коммуникации
-- По откликам, которые заканчиваются приглашением, работодатели в среднем быстрее начинают коммуникацию с кандидатом, чем по остальным откликам.
-- Проверим медианное время до первой коммуникации, долю откликов с коммуникацией и, как дополнительную характеристику, долю первых контактов через сообщение.

-- Гипотеза 2. Интенсивность коммуникации
-- Отклики, завершившиеся приглашением, сопровождаются более активным взаимодействием.
-- Сравним среднее количество коммуникаций, долю откликов с хотя бы одним звонком и долю откликов, где использовались оба канала: и звонки, и сообщения.

-- Запрос по Гипотезе 1:
    WITH event_messages AS (
        SELECT
            m.response_id,
            m.message_id AS event_id,
            m.sent_at AS event_at,
            'message' AS event_type
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sender_role = 'employer'
            AND m.sent_at >= r.created_at
            AND m.sent_at < r.created_at + INTERVAL '7 days'
    ),
    event_calls AS (
        SELECT
            c.response_id,
            c.call_id AS event_id,
            c.call_at AS event_at,
            'call' AS event_type
        FROM calls c
        INNER JOIN responses r ON c.response_id = r.response_id
        WHERE c.caller_role = 'employer'
            AND c.call_at >= r.created_at
            AND c.call_at < r.created_at + INTERVAL '7 days'
    ),
    events AS (
        SELECT * FROM event_messages
        UNION ALL
        SELECT * FROM event_calls
    ),
    timeline AS (
        SELECT
            response_id,
            event_at,
            event_type,
            ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number
        FROM events
    ),
    response_datamart AS (
        SELECT
            r.response_id,
            CASE WHEN r.status = 'invited' THEN 'invited' ELSE 'other' END AS invitation_group,
            COUNT(t.event_at) AS count_events,
            MIN(t.event_at) - r.created_at AS time_to_first_comm,
            MAX(t.event_type) FILTER (WHERE t.event_number = 1) AS first_event_type
        FROM responses r
        LEFT JOIN timeline t ON r.response_id = t.response_id
        GROUP BY r.response_id, r.status, r.created_at
    )

    SELECT
        invitation_group,
        COUNT(*) AS count_responses,
        COUNT(*) FILTER (WHERE count_events > 0) AS count_with_comm,
        ROUND(COUNT(*) FILTER (WHERE count_events > 0) * 100.0 / NULLIF(COUNT(*), 0), 2) AS comm_percentage,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM time_to_first_comm) / 3600.0) AS median_first_comm_hours,
        COUNT(*) FILTER (WHERE first_event_type = 'message') AS count_first_message,
        ROUND(COUNT(*) FILTER (WHERE first_event_type = 'message') * 100.0 / NULLIF(COUNT(*) FILTER (WHERE count_events > 0), 0), 2) AS first_message_percentage
    FROM response_datamart
    GROUP BY invitation_group
    ORDER BY invitation_group;

-- Использую EXTRACT(EPOCH ...), чтобы корректно перевести временной интервал в число секунд. Это новая конструкция, которую я использовал, чтобы получить числовое значение медианы.
-- Здесь обратился к нейронке, потому что до этого я просто вычитал одну дату из другой и получал значение типа interval. 


-- Запрос 2:
    WITH event_messages AS (
        SELECT
            m.response_id,
            m.message_id AS event_id,
            'message' AS event_type
        FROM messages m
        INNER JOIN responses r ON m.response_id = r.response_id
        WHERE m.sender_role = 'employer'
            AND m.sent_at >= r.created_at
            AND m.sent_at < r.created_at + INTERVAL '7 days'
    ),
    event_calls AS (
        SELECT
            c.response_id,
            c.call_id AS event_id,
            'call' AS event_type
        FROM calls c
        INNER JOIN responses r ON c.response_id = r.response_id
        WHERE c.caller_role = 'employer'
            AND c.call_at >= r.created_at
            AND c.call_at < r.created_at + INTERVAL '7 days'
    ),
    events AS (
        SELECT * FROM event_messages
        UNION ALL
        SELECT * FROM event_calls
    ),
    response_datamart AS (
        SELECT
            r.response_id,
            CASE WHEN r.status = 'invited' THEN 'invited' ELSE 'other' END AS invitation_group,
            COUNT(e.event_id) AS count_events,
            COUNT(e.event_id) FILTER (WHERE e.event_type = 'call') AS count_calls,
            COUNT(e.event_id) FILTER (WHERE e.event_type = 'message') AS count_messages
        FROM responses r
        LEFT JOIN events e ON r.response_id = e.response_id
        GROUP BY r.response_id, r.status
    )

    SELECT
        invitation_group,
        COUNT(*) AS count_responses,
        ROUND(AVG(count_events), 2) AS avg_events,
        COUNT(*) FILTER (WHERE count_calls > 0) AS count_with_calls,
        ROUND(COUNT(*) FILTER (WHERE count_calls > 0) * 100.0 / NULLIF(COUNT(*), 0), 2) AS calls_percentage,
        COUNT(*) FILTER (WHERE count_calls > 0 AND count_messages > 0) AS count_both_channels,
        ROUND(COUNT(*) FILTER (WHERE count_calls > 0 AND count_messages > 0) * 100.0 / NULLIF(COUNT(*), 0), 2) AS both_channels_percentage
    FROM response_datamart
    GROUP BY invitation_group
    ORDER BY invitation_group;

-- Вывод по Запросу 1:
-- 1. Количество откликов (count_responses): invited - 92, other - 536.
-- 2. Откликов с коммуникацией (count_with_comm): invited - 54, other - 328.
-- 3. Доля откликов с коммуникацией (comm_percentage): invited - 58.70%, other - 61.19%.ƒ
-- 4. Медианное время до первой коммуникации (median_first_comm_hours): invited - 51.08 часа, other - 54.67 часа.
-- 5. Количество откликов, где первая коммуникация - сообщение (count_first_message): invited - 43, other - 271.
-- 6. Доля первых сообщений среди откликов с коммуникацией (first_message_percentage): invited - 79.63%, other - 82.62%.

-- Итог: гипотеза частично подтверждается. По приглашённым откликам работодатели начинают коммуникацию быстрее на 3.58 часа по медиане.
-- Однако доля откликов с коммуникацией у invited ниже на 2.49%., а доля первых сообщений ниже на 2.99%
-- Различия небольшие, явную связь между скоростью ответа и приглашением установить нельзя.


-- Вывод по Запросу 2:
-- 1. Количество откликов (count_responses): invited - 92, other - 536.
-- 2. Среднее количество коммуникаций на отклик (avg_events): invited - 1.63, other - 1.76.
-- 3. Количество откликов хотя бы с одним звонком (count_with_calls): invited - 15, other - 88.
-- 4. Доля откликов со звонками (calls_percentage): invited - 16.30%, other - 16.42%.
-- 5. Количество откликов с обоими каналами (count_both_channels): invited - 8, other - 57.
-- 6. Доля откликов с обоими каналами (both_channels_percentage): invited - 8.70%, other - 10.63%.

-- Итог: гипотеза не подтверждается. У приглашённых откликов среднее количество коммуникаций ниже на 0.13.
-- Доля откликов со звонками практически одинаковая (разница 0.12%), а оба канала используются у invited реже на 1.93%
-- Таким образом, более интенсивная коммуникация не оказалась характерной для приглашённых откликов.

-- Ограничение исследования:
-- В группу other входят не только rejected, но и new/viewed, по которым процесс найма может ещё продолжаться.
-- Учитываются только коммуникации работодателя за первые 7 дней после отклика.
-- Также неизвестно точное время получения статуса invited, поэтому часть коммуникаций могла произойти уже после приглашения.
-- Найденные различия показывают связь показателей со статусом, но не доказывают зависимость.


-- 8: ИТОГ ИССЛЕДОВАНИЯ

-- Вывод:
-- 1) Всего проанализировано 628 откликов, из которых 398 (63.4%) имели хотя бы одну коммуникацию в первые 7 дней, а 230 (36.6%) остались без зафиксированного общения в этот период.
-- 2) Работодатели чаще используют переписку, чем звонки: в едином слое коммуникаций оказалось 1976 сообщений против 168 звонков, а первая коммуникация начиналась с сообщения в 303 случаях против 95 звонков.
-- 3) При этом скорость и качество обработки откликов различаются между работодателями: например, компании 103 и 101 обработали 171 и 161 ответа в переписке соответственно, удерживая медианное время ответа около 4.5 часа.
-- 4) Дополнительно исследовал метаданные 988 сообщений работодателей: 628 отправлены через web и 360 через mobile_app, причём доля непрочитанных составила 8.28% и 10% соответственно.
-- 5) Проверка первой гипотезы показала, что по приглашённым откликам работодатели начинают коммуникацию немного быстрее: медиана составляет 51.08 часа против 54.67 часа у остальных, то есть разница около 3.6 часа.
-- 6) Однако более интенсивное общение не оказалось характерным для приглашённых: среднее количество коммуникаций составило 1.63 против 1.76, а доля откликов с использованием одновременно сообщений и звонков — 8.70% против 10.63%.
-- 7) Таким образом, по результатам исследования нельзя утверждать, что большее количество контактов повышает вероятность приглашения, возможно, важнее своевременность первого ответа и содержание коммуникации, но это требует дополнительной проверки.
-- 8) Ограничение анализа: 8 звонков не имеет response_id, а группа откликов без приглашения включает статусы new и viewed, по которым процесс найма ещё может продолжаться; кроме того, мы не знаем точное время получения приглашения.
-- 9) В дальнейшем я бы исследовал, как содержание первых сообщений работодателя и время принятия решения о приглашении связаны с результатом отклика, для чего запросил бы историю изменений статусов и более подробные данные о содержании коммуникаций.
-- 10) В ходе просмотра лекции было обнаружено 32 котика :)