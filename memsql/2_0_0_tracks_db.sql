CREATE DATABASE IF NOT EXISTS tracks_db PARTITIONS 16;
USE tracks_db;

CREATE TABLE `db_schema_version` (
  `row_guid` varchar(32) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `version_num` int(11) NOT NULL,
  `version_str` varchar(25) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `deploy_start` datetime NOT NULL DEFAULT '1900-01-01 00:00:00',
  `deploy_end` datetime NOT NULL DEFAULT '1900-01-01 00:00:00',
  `is_success` enum('true','false','') CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`version_num`,`row_guid`)
);

CREATE TABLE `db_errors_msg_log` (
  `row_guid` varchar(32) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `row_datetime` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `procedure_name` varchar(256) CHARACTER SET utf8 COLLATE utf8_general_ci DEFAULT NULL,
  `error_msg` varchar(512) CHARACTER SET utf8 COLLATE utf8_general_ci DEFAULT NULL,
  KEY `pk_db_errors_msg_log` (`row_datetime`,`row_guid`) /*!90619 USING CLUSTERED COLUMNSTORE */
  /*!90618 , SHARD KEY () */ 
) /*!90621 AUTOSTATS_ENABLED=TRUE */;


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
INSERT INTO db_schema_version (row_guid,version_num,version_str,deploy_start) VALUES (get_guid(),200,'19.03.10',NOW());

DELIMITER // 
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name VARCHAR(256),_error_msg VARCHAR(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;

CREATE TABLE `tracks_in_memory` (
  `track_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `source_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `creation_date` as DATE(creation_datetime) PERSISTED date,
  `creation_datetime` datetime NOT NULL,
  `features` varbinary(2048) NOT NULL,
  /*!90618 SHARD */ KEY `s_tracks_in_memory` (`creation_date`,`source_id`,`detection_type`),
  PRIMARY KEY (`track_id`,`creation_date`,`source_id`,`detection_type`)
);

CREATE TABLE `tracks` (
  `track_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `source_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `creation_date` as DATE(creation_datetime) PERSISTED date,
  `creation_datetime` datetime NOT NULL,
  `features` varbinary(2048) NOT NULL,
  `fe_quality` float NOT NULL,
  `detections` JSON NOT NULL,
  `collate_id` varchar(36) NULL,
  `gender` tinyint(4) NULL,
  KEY tracks_pk (`track_id`,`creation_date`,`detection_type`) USING CLUSTERED COLUMNSTORE
);

CREATE TABLE `tracks_pipeline_errors` (
  `guid` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `creation_datetime` datetime NOT NULL,
  `json_data` text NULL,
  KEY tracks_pipeline_errors_pk (`guid`) USING CLUSTERED COLUMNSTORE
);


DELIMITER //
CREATE OR REPLACE PROCEDURE load_detection(batch QUERY(track json))
AS
DECLARE
	err_msg VARCHAR(512) = '';
BEGIN
	BEGIN
		INSERT IGNORE INTO `tracks`
		(`track_id`,
		`source_id`,
		`detection_type`,
		`creation_datetime`,
		`features`,
		`fe_quality`,
		`detections`,
		`collate_id`,
		`gender`)
		SELECT
			track::$track_id,
			track::$source_id,
			track::%detection_type,
			STR_TO_DATE(track::$creation_datetime,'%Y%m%d%H%i%S'),			
			JSON_ARRAY_PACK(track::features),
			track::%fe_quality,
			track::detections,
			track::$collate_id,
			track::%gender
		FROM batch;

		INSERT IGNORE INTO `tracks_in_memory`
		(`track_id`,
		`source_id`,
		`detection_type`,
		`creation_datetime`,
		`features`)
		SELECT
			track::$track_id,
			track::$source_id,
			track::%detection_type,
			STR_TO_DATE(track::$creation_datetime,'%Y%m%d%H%i%S'),			
			JSON_ARRAY_PACK(track::features)
		FROM batch;
	EXCEPTION WHEN OTHERS THEN
			err_msg = exception_message();
			CALL insert_error_row('load_detection',err_msg);
			INSERT INTO `tracks_db`.`tracks_pipeline_errors`
			(`guid`,
			`creation_datetime`,
			`json_data`)
			SELECT get_guid(),NOW(),track
			FROM batch;
			RAISE;
	END;
END //
DELIMITER ;


DELIMITER //
CREATE OR REPLACE PROCEDURE get_track(_track_id VARCHAR(36),_creation_date VARCHAR(50)) 
AS
DECLARE
BEGIN
  ECHO SELECT hex(features) as features_hex
  FROM tracks_in_memory
  WHERE track_id = _track_id
  AND creation_date = _creation_date;
END //
DELIMITER ;


DELIMITER //
CREATE OR REPLACE PROCEDURE search_by_features(_features_hex VARCHAR(4096),_start_datetime datetime,_end_datetime datetime,_detection_type tinyint,_source_id VARCHAR(36),_score_threshold float, _top_results INT) 
AS
DECLARE 
	min_memory_day DATE;
    max_memory_day DATE;
BEGIN

  min_memory_day = SCALAR('SELECT MIN(creation_date) FROM tracks_in_memory', QUERY(a DATE));
  max_memory_day = SCALAR('SELECT MAX(creation_date) FROM tracks_in_memory', QUERY(a DATE));
  
  DROP TABLE IF EXISTS temp_search_results;
  CREATE TEMPORARY TABLE temp_search_results (track_id VARCHAR(36),source_id VARCHAR(36),score float);
  
  IF _source_id = "" THEN
      # start is in memory no need for disk!
	  IF min_memory_day >= DATE(_start_datetime) THEN
		INSERT INTO temp_search_results
        SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM tracks_in_memory
		  WHERE detection_type = _detection_type
		  AND creation_date >= DATE(_start_datetime)
		  AND creation_date <= DATE(_end_datetime)
		  AND creation_datetime >= _start_datetime
		  AND creation_datetime <= _end_datetime
		  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
          ORDER BY score DESC LIMIT _top_results;		
	  ELSE
        # end date is not in memeory, only disk needed
		IF min_memory_day > DATE(_end_datetime) THEN
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM tracks
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
			  FROM tracks_in_memory
			  WHERE detection_type = _detection_type
			  AND creation_date <= DATE(_end_datetime)
			  AND creation_datetime <= _end_datetime
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
              
			# get all disk ending in memory
            INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM tracks
			  WHERE detection_type = _detection_type
              AND creation_date >= DATE(_start_datetime)
			  AND creation_date < min_memory_day
              AND creation_datetime >= _start_datetime
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
        END IF;
	END IF;
  # Filter Source
  ELSE
      # start is in memory no need for disk!
	  IF min_memory_day >= DATE(_start_datetime) THEN
		INSERT INTO temp_search_results
        SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM tracks_in_memory
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
		IF min_memory_day > DATE(_end_datetime) THEN
			INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM tracks
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
			  FROM tracks_in_memory
			  WHERE detection_type = _detection_type
			  AND creation_date <= DATE(_end_datetime)
			  AND creation_datetime <= _end_datetime
			  AND source_id = _source_id
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
              
			# get all disk ending in memory
            INSERT INTO temp_search_results
			SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
			  FROM tracks
			  WHERE detection_type = _detection_type
              AND creation_date >= DATE(_start_datetime)
			  AND creation_date < min_memory_day
              AND creation_datetime >= _start_datetime
			  AND source_id = _source_id
			  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
              ORDER BY score DESC LIMIT _top_results;
        END IF;
	END IF;
  END IF;
  ECHO SELECT track_id,source_id,score FROM temp_search_results ORDER BY score DESC LIMIT _top_results;
  DROP TABLE IF EXISTS temp_search_results;
END //
DELIMITER ;


DELIMITER // 
CREATE OR REPLACE PROCEDURE delete_track(_track_id VARCHAR(36),_source_id VARCHAR(24),_detection_type TINYINT)
AS 
DECLARE
err_msg VARCHAR(512) = '';
row_c INTEGER = 0;
BEGIN
    BEGIN
    START TRANSACTION;
    
  DELETE FROM tracks_in_memory 
  WHERE detection_type = _detection_type
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
CREATE OR REPLACE PROCEDURE delete_tracks_by_source_id(_source_id char(24))
AS
DECLARE 
    row_count int;
   	total_row_count int=0;
BEGIN
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM tracks_in_memory 
    WHERE source_id = _source_id
    LIMIT 50000;
    row_count = row_count();
    total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;


DELIMITER // 
CREATE OR REPLACE PROCEDURE delete_tracks_by_creation_date(_creation_date DATE)
AS
DECLARE 
    row_count INTEGER;
    total_row_count INTEGER=0;
BEGIN
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM tracks_in_memory 
    WHERE creation_date = _creation_date
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;

DELIMITER //
CREATE PROCEDURE get_match_locations(suspect1_track_id varchar(36), suspect2_track_id varchar(36), score FLOAT, time_frame_min int) AS
  DECLARE
     f_s1 varbinary(2048);
     f_s2 varbinary(2048);
  BEGIN
  f_s1 = SCALAR("select features from tracks_in_memory where track_id = '"  || suspect1_track_id || "' limit 1", QUERY(feat varbinary(2048)));
  f_s2 = SCALAR("select features from tracks_in_memory where track_id = '"  || suspect2_track_id || "' limit 1", QUERY(feat varbinary(2048)));
  DROP TABLE IF EXISTS results_found;
  DROP TABLE IF EXISTS suspect1_tracks;
  DROP TABLE IF EXISTS suspect2_tracks;
  CREATE TEMPORARY TABLE results_found(source_id char(24), suspect1_track_id char(36), suspect1_score double, suspect2_track_id char(36), suspect2_score double);
  
  CREATE TEMPORARY TABLE suspect1_tracks AS
    SELECT track_id, source_id, track_datetime,DOT_PRODUCT(features, f_s1) as score
    FROM tracks_in_memory 
    where DOT_PRODUCT(features, f_s1) >= score
    and track_id != suspect1_track_id;
    
  CREATE TEMPORARY TABLE suspect2_tracks AS
    SELECT track_id, source_id, track_datetime,DOT_PRODUCT(features, f_s2) as score
    FROM tracks_in_memory 
    where DOT_PRODUCT(features, f_s2) >= score
    and track_id != suspect2_track_id;
  
  
  insert into results_found
  select distinct s1.source_id, s1.track_id as suspect1_track_ids, s1.score as suspect1_score, s2.track_id as suspect2_track_ids, s2.score as suspect2_score
  from suspect1_tracks s1
  join suspect2_tracks s2
  on s1.source_id = s2.source_id
  and s1.track_datetime between ADDDATE(s2.track_datetime,INTERVAL -(time_frame_min) MINUTE) and ADDDATE(s2.track_datetime,INTERVAL time_frame_min MINUTE);
 ECHO SELECT source_id, suspect1_track_ids, suspect1_score, suspect2_track_ids, suspect2_score FROM results_found;
  DROP TABLE IF EXISTS results_found;
  DROP TABLE IF EXISTS suspect1_tracks;
  DROP TABLE IF EXISTS suspect2_tracks;
  END //
DELIMITER ;

DELIMITER // 
CREATE OR REPLACE PROCEDURE delete_tracks_older_than_creation_date(_creation_date DATE)
AS
DECLARE 
    row_count INTEGER;
    total_row_count INTEGER=0;
BEGIN
  row_count = 1;
  WHILE row_count > 0 LOOP
    DELETE FROM tracks_in_memory 
    WHERE creation_date <= _creation_date
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;


#call db_purge_memory_tracks_by_min_creation_date();
# Automatic Purge Date by Memory Limit
DELIMITER // 
CREATE OR REPLACE PROCEDURE db_purge_memory_tracks_by_min_creation_date()
AS
DECLARE 
    row_count INTEGER;
    total_row_count INTEGER=0;
    err_msg VARCHAR(512);
    q_min_date QUERY(min_date date) = SELECT min(creation_date) FROM tracks_in_memory;
    min_Date DATE;
BEGIN
  min_Date = SCALAR(q_min_date);
  BEGIN
  row_count = 1;
  START TRANSACTION;
  WHILE row_count > 0 LOOP
    DELETE FROM tracks_in_memory 
    WHERE creation_date = min_Date
    LIMIT 50000;
    row_count = row_count();
   	total_row_count += row_count;
  END LOOP;
  COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    err_msg = exception_message();
    CALL insert_error_row('db_purge_memory_tracks_by_min_creation_date',err_msg );
    ECHO SELECT -1 as rows_deleted;
  END;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;

#update finishe of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 200;
