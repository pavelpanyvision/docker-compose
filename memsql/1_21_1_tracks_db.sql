CREATE DATABASE IF NOT EXISTS tracks_db PARTITIONS 16;
USE tracks_db;

CREATE TABLE IF NOT EXISTS db_schema_version (
  row_guid VARCHAR(32) NOT NULL,
  version_num INTEGER NOT NULL,
  version_str VARCHAR(25) NOT NULL,
  deploy_start DATETIME NOT NULL DEFAULT '1900-01-01 00:00:00',
  deploy_end DATETIME NOT NULL DEFAULT '1900-01-01 00:00:00',
  is_success ENUM('true','false', '') DEFAULT '' NOT NULL,
  PRIMARY KEY `pk_db_schema_version` (version_num,row_guid)
);

CREATE TABLE IF NOT EXISTS db_errors_msg_log (
  row_guid VARCHAR(32) NOT NULL,
  row_datetime timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  procedure_name VARCHAR(256) NULL,
  error_msg VARCHAR(512) NULL,
  KEY `pk_db_errors_msg_log` (row_datetime,row_guid) USING CLUSTERED COLUMNSTORE
) AUTOSTATS_ENABLED=TRUE;


DELIMITER //
CREATE OR REPLACE FUNCTION get_guid() RETURNS VARCHAR(36) AS
DECLARE
guid VARCHAR(36) = CONCAT(
        SUBSTRING(SHA1(RAND()), 1, 8),
        '-',
        SUBSTRING(SHA1(RAND()), 1, 4),
        '-',
        SUBSTRING(SHA1(RAND()), 1, 4),
        '-',
        SUBSTRING(SHA1(RAND()), 1, 4),
        '-',
        SUBSTRING(SHA1(RAND()), 1, 12)
    );
  BEGIN
    RETURN guid;
  END //
DELIMITER ;


#insert first version
INSERT INTO db_schema_version (row_guid,version_num,version_str,deploy_start) VALUES (get_guid(),1,'19.01.10',NOW());

DELIMITER // 
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name varchar(256),_error_msg varchar(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;

CREATE TABLE IF NOT EXISTS `detection` (
  `track_id` VARCHAR(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `source_id` VARCHAR(24) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `creation_date` AS DATE(creation_datetime) PERSISTED DATE,
  `creation_datetime` datetime NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `features` varbinary(2048) DEFAULT NULL,
  `start_frame` INTEGER NOT NULL DEFAULT -1,
  `end_frame` INTEGER NOT NULL DEFAULT -1,
  `positions` JSON NOT NULL,
  SHARD KEY `s_detection` (creation_date,source_id,detection_type),
  KEY `pk_detection` (track_id,creation_date,source_id,detection_type) USING CLUSTERED COLUMNSTORE
) AUTOSTATS_ENABLED=TRUE;


CREATE TABLE IF NOT EXISTS `detection_in_memory` (
  `track_id` VARCHAR(36) NOT NULL,
  `source_id` VARCHAR(24) NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `creation_date` AS DATE(creation_datetime) PERSISTED DATE,
  `creation_datetime` datetime NOT NULL,
  `features` varbinary(2048) NOT NULL,
  SHARD KEY `s_detection_in_memory` (creation_date,source_id,detection_type),
  PRIMARY KEY `pk_detection_in_memory` (track_id,creation_date,source_id,detection_type)
);

DELIMITER //
CREATE OR REPLACE PROCEDURE save_tracks(_array_of_tracks json) 
AS
DECLARE 
    current_json JSON;
    current_track_id VARCHAR(36);
    array_length INTEGER = JSON_LENGTH(_array_of_tracks);
   	err_msg VARCHAR(512) = '';
BEGIN
  DROP TABLE IF EXISTS save_tracks_result;
  CREATE TEMPORARY TABLE save_tracks_result(track_id char(36),is_success varchar(10),error_msg varchar(512));
  FOR i in 0 .. (array_length-1) LOOP
  BEGIN
  current_json = JSON_EXTRACT_JSON(_array_of_tracks,i);
  current_track_id = JSON_EXTRACT_STRING(current_json,'track_id');
  START TRANSACTION;
  INSERT INTO detection
    (track_id, source_id, creation_datetime, detection_type, features, start_frame, end_frame, positions)
    VALUES(
        current_track_id,
        JSON_EXTRACT_STRING(current_json,'source_id'),
        STR_TO_DATE(JSON_EXTRACT_STRING(current_json,'creation_datetime'),'%Y%m%d%H%i%S'),
        JSON_EXTRACT_DOUBLE(current_json,'detection_type'),
        JSON_ARRAY_PACK(JSON_EXTRACT_JSON(current_json,'features')),
        JSON_EXTRACT_DOUBLE(current_json,'start_frame'),
        JSON_EXTRACT_DOUBLE(current_json,'end_frame'),
        JSON_EXTRACT_JSON(current_json,'positions')    
    );
  INSERT INTO detection_in_memory
    (track_id, source_id, creation_datetime, detection_type, features)
    VALUES(
        current_track_id,
        JSON_EXTRACT_STRING(current_json,'source_id'),
        STR_TO_DATE(JSON_EXTRACT_STRING(current_json,'creation_datetime'),'%Y%m%d%H%i%S'),
        JSON_EXTRACT_DOUBLE(current_json,'detection_type'),
        JSON_ARRAY_PACK(JSON_EXTRACT_JSON(current_json,'features'))   
    );
    COMMIT;
	INSERT INTO save_tracks_result (track_id,is_success,error_msg) VALUES (current_track_id,"success","");
   EXCEPTION WHEN OTHERS THEN
	ROLLBACK;
	err_msg = exception_message();
	CALL insert_error_row('save_tracks',err_msg);
    INSERT INTO save_tracks_result (track_id,is_success,error_msg) VALUES (current_track_id,"failed",err_msg);
   END;
  END LOOP; 
  ECHO SELECT track_id,is_success,error_msg as save_tracks_result;
  DROP TABLE IF EXISTS save_tracks_result;
END //
DELIMITER ;

DELIMITER //
CREATE OR REPLACE PROCEDURE get_track(_track_id VARCHAR(36),_source_id VARCHAR(24),_detection_type tinyint,_creation_date date) 
AS
DECLARE
BEGIN
  ECHO SELECT hex(features) as features_hex,start_frame,end_frame,positions
  FROM detection
  WHERE track_id = _track_id
  AND source_id = _source_id
  AND detection_type = _detection_type
  AND creation_date = _creation_date;
END //
DELIMITER ;



DELIMITER //
CREATE OR REPLACE PROCEDURE search_by_features(_features_hex varchar(4096),_start_datetime datetime,_end_datetime datetime,_detection_type tinyint,_source_id varchar(24),_score_threshold float, _top_results INT) 
AS
DECLARE 
	rows_min_c INT = 0;
    rows_max_c INT = 0;
BEGIN
  DROP TABLE IF EXISTS min_memory_day;
  CREATE TEMPORARY TABLE min_memory_day(min_date date);
  DROP TABLE IF EXISTS max_memory_day;
  CREATE TEMPORARY TABLE max_memory_day(max_date date);
  
  INSERT INTO min_memory_day SELECT creation_date FROM detection_in_memory
  WHERE DATE(_start_datetime) = creation_date LIMIT 1;
  rows_min_c = row_count();
  
  INSERT INTO max_memory_day SELECT creation_date FROM detection_in_memory
  WHERE DATE(_end_datetime) = creation_date LIMIT 1;
  rows_max_c = row_count();
  
  DROP TABLE IF EXISTS temp_search_results;
  CREATE TEMPORARY TABLE temp_search_results (track_id char(36),source_id char(24),score float);
  
  IF _source_id = "" THEN
      # start is in memory no need for disk!
	  IF rows_min_c > 0 THEN
		INSERT INTO temp_search_results
        SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM detection_in_memory
		  WHERE detection_type = _detection_type
		  AND creation_date >= DATE(_start_datetime)
		  AND creation_date <= DATE(_end_datetime)
		  AND creation_datetime >= _start_datetime
		  AND creation_datetime <= _end_datetime
		  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
          ORDER BY score DESC LIMIT _top_results;		
	  ELSE
        # end date is not in memeory, only disk needed
		IF rows_max_c = 0 THEN
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection
			  WHERE detection_type = _detection_type
			  AND creation_date >= DATE(_start_datetime)
			  AND creation_date < DATE(_end_datetime)
			  AND creation_datetime >= _start_datetime
			  AND creation_datetime <= _end_datetime
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;        
        ELSE
			# end in memory, start in disk, get all memory...
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection_in_memory
			  WHERE detection_type = _detection_type
			  AND creation_date <= DATE(_end_datetime)
			  AND creation_datetime <= _end_datetime
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
              
			# get all disk ending in memory
            INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection_in_memory
			  WHERE detection_type = _detection_type
              AND creation_date >= DATE(_start_datetime)
			  AND creation_date < (select MIN(creation_date) from detection_in_memory)
              AND creation_datetime >= _start_datetime
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
        END IF;
	END IF;
  # Filter Source
  ELSE
        # start is in memory no need for disk!
	  IF rows_min_c > 0 THEN
		INSERT INTO temp_search_results
        SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM detection_in_memory
		  WHERE detection_type = _detection_type
		  AND creation_date >= DATE(_start_datetime)
		  AND creation_date <= DATE(_end_datetime)
		  AND creation_datetime >= _start_datetime
		  AND creation_datetime <= _end_datetime
          AND source_id = _source_id
		  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
          ORDER BY score DESC LIMIT _top_results;		
	  ELSE
        # end date is not in memeory, only disk needed
		IF rows_max_c = 0 THEN
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection
			  WHERE detection_type = _detection_type
			  AND creation_date >= DATE(_start_datetime)
			  AND creation_date < DATE(_end_datetime)
			  AND creation_datetime >= _start_datetime
			  AND creation_datetime <= _end_datetime
              AND source_id = _source_id
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;        
        ELSE
			# end in memory, start in disk, get all memory...
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection_in_memory
			  WHERE detection_type = _detection_type
			  AND creation_date <= DATE(_end_datetime)
			  AND creation_datetime <= _end_datetime
              AND source_id = _source_id
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
              
			# get all disk ending in memory
            INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM detection
			  WHERE detection_type = _detection_type
              AND creation_date >= DATE(_start_datetime)
			  AND creation_date < (select MIN(creation_date) from detection_in_memory)
              AND creation_datetime >= _start_datetime
              AND source_id = _source_id
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
        END IF;
	END IF;  
  END IF;
  ECHO SELECT track_id,source_id,score FROM temp_search_results ORDER BY score DESC LIMIT _top_results;
  DROP TABLE IF EXISTS min_memory_day;
  DROP TABLE IF EXISTS max_memory_day;
  DROP TABLE IF EXISTS temp_search_results;
END //
DELIMITER ;


DELIMITER // 
CREATE OR REPLACE PROCEDURE delete_track(_track_id VARCHAR(36),_source_id VARCHAR(24),_detection_type tinyint,_creation_date date)
AS 
DECLARE
err_msg VARCHAR(512) = '';
row_c INTEGER = 0;
BEGIN
    BEGIN
    START TRANSACTION;
  DELETE FROM detection 
  WHERE detection_type = _detection_type
  AND creation_date = _creation_date
  AND track_id = _track_id
  AND source_id = _source_id;
  row_c += row_count();
 
  DELETE FROM detection_in_memory 
  WHERE detection_type = _detection_type
  AND creation_date = _creation_date
  AND track_id = _track_id
  AND source_id = _source_id;
  row_c += row_count();
    COMMIT;
    IF row_c = 0 THEN
        ECHO SELECT _track_id as track_id,'false' as is_deleted, "didn't find track_id in db" as error_msg;
    ELSE
        ECHO SELECT _track_id as track_id,'true' as is_deleted, '' as error_msg;
    END IF;
    EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    err_msg = exception_message();
    CALL insert_error_row('delete_track',err_msg );
    ECHO SELECT _track_id as track_id,'false' as is_deleted, err_msg as error_msg;
    END;
END // 
DELIMITER ;
 
 
DELIMITER // 
CREATE OR REPLACE PROCEDURE delete_tracks_by_creation_date(_creation_date date)
AS
DECLARE 
    row_count int;
    total_row_count int=0;
BEGIN
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM detection 
    WHERE creation_date = _creation_date
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM detection_in_memory 
    WHERE creation_date = _creation_date
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;



DELIMITER //
CREATE OR REPLACE PROCEDURE delete_tracks_by_source_id(_source_id char(24))
AS
DECLARE 
    row_count int;
   	total_row_count int=0;
BEGIN
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM detection 
    WHERE source_id = _source_id
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM detection_in_memory 
    WHERE source_id = _source_id
    LIMIT 50000;
    row_count = row_count();
    total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;

#update finishe of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 1;
