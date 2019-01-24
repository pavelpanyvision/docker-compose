CREATE DATABASE IF NOT EXISTS tracks_db PARTITIONS 8;
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
  row_guid CHAR(32) NOT NULL,
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
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name VARCHAR(256),_error_msg VARCHAR(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;

CREATE TABLE IF NOT EXISTS `detection` (
  `track_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `source_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `pipe_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `collate_id` varchar(36) CHARACTER SET utf8 COLLATE utf8_general_ci NULL,
  `detection_type` tinyint(4) NOT NULL,
  `creation_date` AS DATE(creation_datetime) PERSISTED DATE,
  `creation_datetime` datetime NOT NULL,
  `time_base` bigint NOT NULL,
  `features` varbinary(2048) DEFAULT NULL,
  `detection_quality_score` FLOAT NOT NULL DEFAULT 0.0,
  `detections` JSON NOT NULL,
  `zoom_in_imgs` JSON NOT NULL,
  `zoom_out_imgs` JSON NOT NULL,
  `close_matches` JSON NOT NULL,
  SHARD KEY `s_detection` (creation_date,source_id,detection_type),
  KEY `pk_detection` (track_id,creation_date,source_id,detection_type) USING CLUSTERED COLUMNSTORE
) AUTOSTATS_ENABLED=TRUE;


CREATE TABLE IF NOT EXISTS `detection_in_memory` (
  `track_id` binary(36) NOT NULL,
  `source_id` binary(36) NOT NULL,
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
  CREATE TEMPORARY TABLE save_tracks_result(track_id VARCHAR(36),is_success VARCHAR(10),error_msg VARCHAR(512));
  FOR i in 0 .. (array_length-1) LOOP
  BEGIN
  current_json = JSON_EXTRACT_JSON(_array_of_tracks,i);
  current_track_id = JSON_EXTRACT_STRING(current_json,'track_id');
  START TRANSACTION;
  INSERT INTO detection
    (track_id, source_id, pipe_id, collate_id, detection_type, creation_datetime, 
    time_base, features, detection_quality_score, detections, zoom_in_imgs, zoom_out_imgs, close_matches)
    VALUES(
        current_track_id,
        current_json::$source_id,
        current_json::$pipe_id,
        current_json::$collate_id,
        current_json::%detection_type,
        STR_TO_DATE(current_json::$creation_datetime,'%Y%m%d%H%i%S'),
        current_json::%time_base,
        JSON_ARRAY_PACK(current_json::features),
        current_json::%detection_quality_score,
        current_json::detections,
        current_json::zoom_in_imgs,
        current_json::zoom_out_imgs,
        current_json::close_matches 
    );
  INSERT INTO detection_in_memory
    (track_id, source_id, creation_datetime, detection_type, features)
    VALUES(
        current_track_id,
        current_json::$source_id,
        STR_TO_DATE(current_json::$creation_datetime,'%Y%m%d%H%i%S'),
        current_json::%detection_type,
        JSON_ARRAY_PACK(current_json::features)
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
CREATE OR REPLACE PROCEDURE get_track(_track_id VARCHAR(36),_source_id VARCHAR(36),_detection_type tinyint,_creation_date date) 
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
CREATE OR REPLACE PROCEDURE search_by_features(_features_hex VARCHAR(4096),_start_datetime datetime,_end_datetime datetime,_detection_type tinyint,_source_id VARCHAR(36),_score_threshold float, _top_results INT) 
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
  CREATE TEMPORARY TABLE temp_search_results (track_id VARCHAR(36),source_id VARCHAR(36),score float);
  
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
          AND source_id = CAST(_source_id AS BINARY(36))
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
              AND source_id = CAST(_source_id AS BINARY(36))
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
CREATE OR REPLACE PROCEDURE delete_track(_track_id VARCHAR(36),_source_id VARCHAR(36),_detection_type tinyint,_creation_date date)
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
  AND track_id = CAST(_track_id AS BINARY(36))
  AND source_id = CAST(_source_id AS BINARY(36));
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
CREATE OR REPLACE PROCEDURE delete_tracks_by_source_id(_source_id varchar(36))
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
    WHERE source_id = CAST(_source_id AS BINARY(36))
    LIMIT 50000;
    row_count = row_count();
    total_row_count += row_count;
  END LOOP;
  ECHO SELECT total_row_count as rows_deleted;
END //
DELIMITER ;



#update finish of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 1;



######################## REID DB #####################################
CREATE DATABASE IF NOT EXISTS reid_db PARTITIONS 8;
USE reid_db;


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
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name VARCHAR(256),_error_msg VARCHAR(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;

CREATE TABLE IF NOT EXISTS `poi` (
  `poi_id` binary(36) NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `groups` json NOT NULL,
  `source_id` binary(36) NOT NULL,
  `feature_id` binary(36) NOT NULL,
  `features` varbinary(2048) DEFAULT NULL,
  KEY `pk_poi` (poi_id, detection_type, feature_id)
);

/*
call save_poi('[{"poi_id": "P_UUID","detection_type": 1,"groups": ["GROUPAID","GROUPCID","GROUPBID"], "features_data": [{"feature_id": "F_UUID","source_id": "S_UUID", "features":[0.324234,0.23432423,0.324234,0.2345]}]},{"poi_id": "P_UUID2","detection_type": 1,"groups": ["GROUPAID","GROUPCID","GROUPBID"], "features_data": [{"feature_id": "F_UUID","source_id": "S_UUID", "features":[0.324234,0.23432423,0.324234,0.2345]}]}]');
*/

DELIMITER //
CREATE OR REPLACE PROCEDURE save_poi(_array_of_tracks json) 
AS
DECLARE 
    current_json JSON;
    current_feature_data JSON;
    current_features_data JSON;
    current_poi_id VARCHAR(36);
    array_length INTEGER = JSON_LENGTH(_array_of_tracks);
    array_features_data_length INTEGER = 0;
    current_detection_type INTEGER;
   	err_msg VARCHAR(512) = '';
BEGIN
  DROP TABLE IF EXISTS save_poi_result;
  CREATE TEMPORARY TABLE save_poi_result(poi_id VARCHAR(36),is_success VARCHAR(10),error_msg VARCHAR(512));
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			current_json = JSON_EXTRACT_JSON(_array_of_tracks,i);
			current_poi_id = current_json::$poi_id;
            current_detection_type = current_json::%detection_type;
			current_features_data = current_json::features_data;
            array_features_data_length = JSON_LENGTH(current_features_data);
			START TRANSACTION;
				# clean exists
                DELETE FROM poi
                WHERE poi_id = CAST(current_poi_id AS BINARY(36));
                # Insert new
                FOR z IN 0 .. (array_features_data_length-1) LOOP
					current_feature_data = JSON_EXTRACT_JSON(current_features_data,z);
					INSERT INTO poi
									(poi_id, detection_type, groups, source_id, feature_id, features) VALUES (
									current_poi_id,
                                    current_detection_type,
                                    current_json::groups,
                                    current_feature_data::$source_id,
                                    current_feature_data::$feature_id,
                                    JSON_ARRAY_PACK(current_feature_data::features)
                                    );
				END LOOP;
			COMMIT;
			INSERT INTO save_poi_result (poi_id,is_success,error_msg) VALUES (current_poi_id,"success","");
			EXCEPTION WHEN OTHERS THEN
				ROLLBACK;
				err_msg = exception_message();
				CALL insert_error_row('save_poi',err_msg);
                INSERT INTO save_poi_result (poi_id,is_success,error_msg) VALUES (current_poi_id,"failed",err_msg);
		END;
  END LOOP;
  ECHO SELECT poi_id as pod_id,is_success as is_success,error_msg as error_msg from save_poi_result;
  DROP TABLE IF EXISTS save_poi_result;
END //
DELIMITER ;

/*
call get_poi('P_UUID');
*/

DELIMITER //
CREATE OR REPLACE PROCEDURE get_poi(_poi_id VARCHAR(36)) 
AS
DECLARE   
    arr ARRAY(RECORD(features_hex varchar(4096)));
    features_hex VARCHAR(4096);
    res_features_arr json = '[]';
BEGIN
  arr = COLLECT(CONCAT("SELECT hex(features) FROM poi WHERE poi_id = CAST('",_poi_id,"' AS BINARY(36))"), QUERY(features_hex varchar(4096)));
  FOR x in arr LOOP
    features_hex = x.features_hex;
    res_features_arr = JSON_ARRAY_PUSH_STRING(res_features_arr,features_hex);
  END LOOP;
  ECHO SELECT res_features_arr as feature_hex_list;
END //
DELIMITER ;


/*
call delete_poi('[{"poi_id": "P_UUID", "detection_type": 1}, {"poi_id": "P_UUID2", "detection_type": 1}]');
*/
DELIMITER //
CREATE OR REPLACE PROCEDURE delete_poi(_array_of_poi_id json) 
AS
DECLARE 
    current_json JSON;
    current_poi_id VARCHAR(36);
    array_length INTEGER = JSON_LENGTH(_array_of_poi_id);
    current_detection_type INTEGER;
    rows_deleted int;
   	err_msg VARCHAR(512) = '';
BEGIN
  DROP TABLE IF EXISTS delete_poi_result;
  CREATE TEMPORARY TABLE delete_poi_result(poi_id VARCHAR(36),is_success VARCHAR(10), rows_del int,error_msg VARCHAR(512));
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			current_json = JSON_EXTRACT_JSON(_array_of_poi_id,i);
			current_poi_id = current_json::$poi_id;
            current_detection_type = current_json::%detection_type;
			START TRANSACTION;
				# clean exists
                DELETE FROM poi
                WHERE poi_id = CAST(current_poi_id AS BINARY(36));
                rows_deleted = row_count();
			COMMIT;
			INSERT INTO delete_poi_result (poi_id,is_success,rows_del,error_msg) VALUES (current_poi_id,"success",rows_deleted,"");
			EXCEPTION WHEN OTHERS THEN
				ROLLBACK;
				err_msg = exception_message();
				CALL insert_error_row('delete_poi',err_msg);
                INSERT INTO delete_poi_result (poi_id,is_success,rows_del,error_msg) VALUES (current_track_id,"failed",0,err_msg);
		END;
  END LOOP;
  ECHO SELECT poi_id as pod_id,is_success as is_success,rows_del as rows_deleted,error_msg as error_msg from delete_poi_result;
  DROP TABLE IF EXISTS delete_poi_result;
END //
DELIMITER ;


DELIMITER //
CREATE OR REPLACE PROCEDURE delete_poi_by_group(_array_of_groups json) 
AS
DECLARE 
    current_group_id VARCHAR(36);
    array_length INTEGER = JSON_LENGTH(_array_of_groups);
    rows_deleted int = 0 ;
   	err_msg VARCHAR(512) = '';
BEGIN
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			
			current_group_id = JSON_EXTRACT_STRING(_array_of_groups,i);
			START TRANSACTION;		
            UPDATE poi
            SET groups = REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(groups,CONCAT(',"',current_group_id,'"'),'','ig'),CONCAT('"',current_group_id,'",'),'','ig'),CONCAT('"',current_group_id,'"'),'','ig')
            WHERE JSON_ARRAY_CONTAINS_STRING(groups, current_group_id);
            
            # delete poi if only 0 groups
            DELETE FROM poi
            WHERE JSON_LENGTH(groups) = 0;
            rows_deleted += row_count();
            COMMIT;
		EXCEPTION WHEN OTHERS THEN
			ROLLBACK;
			err_msg = exception_message();
			CALL insert_error_row('delete_poi_groups',err_msg);
			RAISE;
		END;
  END LOOP;
  ECHO SELECT rows_deleted as rows_deleted;
END //
DELIMITER ;


DELIMITER //
CREATE OR REPLACE PROCEDURE add_features_to_poi(_poi_id varchar(36), _detection_type tinyint, _groups json,_array_of_features json) 
AS
DECLARE 
    current_feature_data JSON;
    array_length INT = JSON_LENGTH(_array_of_features);
   	err_msg VARCHAR(512) = '';
    rows_c INT = 0;
BEGIN
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			current_feature_data = JSON_EXTRACT_JSON(_array_of_features,i);
			START TRANSACTION;
				# Insert new
			INSERT INTO poi
							(poi_id, detection_type, groups, source_id, feature_id, features) VALUES (
							_poi_id,
							_detection_type,
							_groups,
							current_feature_data::$source_id,
							current_feature_data::$feature_id,
							JSON_ARRAY_PACK(current_feature_data::features)
							);
			rows_c += row_count();
			COMMIT;
			EXCEPTION WHEN OTHERS THEN
				ROLLBACK;
				err_msg = exception_message();
				CALL insert_error_row('add_features_to_poi',err_msg);
                RAISE;
		END;
  END LOOP;
  ECHO SELECT rows_c as rows_inserted;
END //
DELIMITER ;

DELIMITER //
CREATE OR REPLACE PROCEDURE remove_features_from_poi(_poi_id varchar(36), _detection_type tinyint, _array_of_features json) 
AS
DECLARE 
    current_feature_data_id JSON;
    array_length INT = JSON_LENGTH(_array_of_features);
   	err_msg VARCHAR(512) = '';
    rows_c INT = 0;
BEGIN
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			current_feature_data_id = JSON_EXTRACT_JSON(_array_of_features,i);
			START TRANSACTION;
			DELETE FROM poi
            WHERE poi_id = CAST(_poi_id AS BINARY(36))
            AND feature_id = CAST(current_feature_data_id AS BINARY(36));
			rows_c += row_count();
			COMMIT;
			EXCEPTION WHEN OTHERS THEN
				ROLLBACK;
				err_msg = exception_message();
				CALL insert_error_row('remove_features_from_poi',err_msg);
                RAISE;
		END;
  END LOOP;
  ECHO SELECT rows_c as rows_deleted;
END //
DELIMITER ;



DELIMITER //
CREATE OR REPLACE PROCEDURE add_poi_to_group(update_json json) 
AS
DECLARE 
    array_length INT;
    current_group_id VARCHAR(36);
   	err_msg VARCHAR(512) = '';
    rows_c INT = 0;
BEGIN
  DROP TABLE IF EXISTS list_of_poi;
  CREATE TEMPORARY TABLE list_of_poi(poi_id BINARY(36));
  current_group_id = update_json::$group_id;
  array_length = JSON_LENGTH(update_json::poi);  
  FOR i IN 0 .. (array_length-1) LOOP
		INSERT INTO list_of_poi (poi_id) VALUES (JSON_EXTRACT_JSON(update_json::poi,i));
  END LOOP;
  BEGIN
	  START TRANSACTION;
	  UPDATE poi
	  SET groups = JSON_ARRAY_PUSH_STRING(groups,current_group_id)
	  WHERE JSON_ARRAY_CONTAINS_STRING(groups,current_group_id) = 0
	  AND poi_id in (select poi_id from list_of_poi);
	  rows_c = row_count();
	  COMMIT;
				EXCEPTION WHEN OTHERS THEN
					ROLLBACK;
					err_msg = exception_message();
					CALL insert_error_row('add_poi_to_group',err_msg);
					RAISE;
  END;
  ECHO SELECT rows_c as rows_update;
  DROP TABLE IF EXISTS list_of_poi;
END //
DELIMITER ;


DELIMITER //
CREATE OR REPLACE PROCEDURE set_groups_to_poi(update_json json) 
AS
DECLARE 
   	err_msg VARCHAR(512) = '';
    rows_c INT = 0;
BEGIN
  BEGIN
	  START TRANSACTION;
	  UPDATE poi
	  SET groups = update_json::groups
	  WHERE poi_id = CAST(update_json::$poi_id AS BINARY(36));
	  rows_c = row_count();
	  COMMIT;
				EXCEPTION WHEN OTHERS THEN
					ROLLBACK;
					err_msg = exception_message();
					CALL insert_error_row('set_groups_to_poi',err_msg);
					RAISE;
  END;
  ECHO SELECT rows_c as rows_update;
END //
DELIMITER ;



#update finishe of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 1;


-- ######################## Kafka To MemSQL  #####################################
-- 
-- DELIMITER //
-- CREATE OR REPLACE PROCEDURE load_detection(batch QUERY(detection json)) 
-- AS
-- BEGIN
--   INSERT INTO `detection`
-- 	(`track_id`,
-- 	`source_id`,
-- 	`creation_datetime`,
-- 	`detection_type`,
-- 	`features`,
-- 	`start_frame`,
-- 	`end_frame`,
-- 	`positions`)
--     SELECT 
-- 		detection::$track_id,
-- 		detection::$source_id,
-- 		STR_TO_DATE(detection::$creation_datetime,'%Y%m%d%H%i%S'),
--         detection::%detection_type,
-- 		JSON_ARRAY_PACK(detection::features),
--         detection::%start_frame,
--         detection::%end_frame,
--         detection::positions
-- 	FROM batch;
--    
--   INSERT INTO `detection_in_memory`
-- 		(`track_id`,
-- 		`source_id`,
-- 		`detection_type`,
-- 		`creation_datetime`,
-- 		`features`)
-- 	SELECT 
-- 		detection::$track_id,
-- 		detection::$source_id,
-- 		detection::%detection_type,
-- 		STR_TO_DATE(detection::$creation_datetime,'%Y%m%d%H%i%S'),
-- 		JSON_ARRAY_PACK(detection::features)
-- 	FROM batch;
-- END //
-- DELIMITER ;
-- 
-- #STOP PIPELINE load_kafka_detection;
-- #DROP PIPELINE load_kafka_detection;
-- 
-- CREATE OR REPLACE PIPELINE load_kafka_detection
-- AS LOAD DATA kafka 'kafka.tls.ai/detection'
-- BATCH_INTERVAL 500
-- INTO PROCEDURE load_detection
-- FORMAT JSON (detection <- %);
-- 
-- ALTER PIPELINE load_kafka_detection SET OFFSETS EARLIEST;
-- 
-- START PIPELINE load_kafka_detection;
-- 
-- ######################## Kafka To MemSQL  #####################################
