
-- Write a query in SQL to obtain the nurses and the block where
-- they are booked for attending the patients on call 

-- Write a query in SQL to obtain the nurses and the block where
-- they are booked for attending the patients on call 

-- Table: nurse 
-- employeed_id |      name       |    position  | registered | ssn
--    101       | Carla Espinosa  | Head Nurse   | True       | 110*****
-- Table: stay
-- stay_id |  patient  |   room  |   start_date   | end_date
--  3251   | 10000001  |   111   |   2018-05-01   | 2018-05-04

SELECT name, employeed_id
FROM nurse
WHERE registered = 'True'
