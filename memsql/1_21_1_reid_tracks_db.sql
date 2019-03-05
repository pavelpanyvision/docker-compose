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
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name VARCHAR(256),_error_msg VARCHAR(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;

CREATE TABLE IF NOT EXISTS `tracks_in_memory` (
  `track_id` VARCHAR(36) NOT NULL,
  `source_id` VARCHAR(24) NOT NULL,
  `detection_type` TINYINT(4) NOT NULL,
  `creation_date` AS DATE(creation_datetime) PERSISTED DATE,
  `creation_datetime` DATETIME NOT NULL,
  `features` VARBINARY(2048) NOT NULL,
  SHARD KEY `s_tracks_in_memory` (creation_date,source_id,detection_type),
  PRIMARY KEY `pk_tracks_in_memory` (track_id,creation_date,source_id,detection_type)
);

DELIMITER //
CREATE OR REPLACE PROCEDURE save_tracks(_track_id VARCHAR(36), _source_id VARCHAR(24), _creation_datetime VARCHAR(50), _detection_type TINYINT, _features JSON) 
AS
DECLARE 
   	err_msg VARCHAR(512) = '';
BEGIN
  BEGIN
    INSERT INTO tracks_in_memory
      (track_id, source_id, creation_datetime, detection_type, features)
    VALUES (_track_id,_source_id,STR_TO_DATE(_creation_datetime,'%Y%m%d%H%i%S'),_detection_type, JSON_ARRAY_PACK(_features))
    COMMIT;
    ECHO SELECT _track_id as track_id,'success' as is_success, '' as error_msg;
  EXCEPTION WHEN OTHERS THEN
	ROLLBACK;
	err_msg = exception_message();
	CALL insert_error_row('save_tracks',err_msg);
    ECHO SELECT _track_id as track_id,'failed' as is_success, err_msg as error_msg;
   END;
END //
DELIMITER ;

DELIMITER //
CREATE OR REPLACE PROCEDURE get_track(_track_id VARCHAR(36),_source_id VARCHAR(24),_detection_type TINYINT) 
AS
DECLARE
BEGIN
  ECHO SELECT hex(features) as features_hex
  FROM tracks_in_memory
  WHERE track_id = _track_id
  AND source_id = _source_id
  AND detection_type = _detection_type;
END //
DELIMITER ;



DELIMITER //
CREATE OR REPLACE PROCEDURE search_by_features(_features_hex VARCHAR(4096),_detection_type TINYINT,_source_id VARCHAR(24),_score_threshold FLOAT, _top_results INT) 
AS
BEGIN
  IF _source_id = "" THEN
        ECHO SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM tracks_in_memory
		  WHERE detection_type = _detection_type
		  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
          ORDER BY score DESC 
          LIMIT _top_results;		
  ELSE
        ECHO SELECT track_id,source_id,DOT_PRODUCT(features,unhex(_features_hex)) as score
		  FROM tracks_in_memory
		  WHERE detection_type = _detection_type
          AND source_id = _source_id
		  AND DOT_PRODUCT(features,unhex(_features_hex)) >= _score_threshold
          ORDER BY score DESC 
          LIMIT _top_results;		
  END IF;
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

# Automatic Purge Date by Memory Limit
DELIMITER // 
CREATE OR REPLACE PROCEDURE db_purge_memory_tracks_by_min_creation_date()
AS
DECLARE 
    row_count INTEGER;
    total_row_count INTEGER=0;
    err_msg VARCHAR(512);
BEGIN
  DROP TABLE IF EXISTS min_memory_day;
  CREATE TEMPORARY TABLE min_memory_day(min_date date);  
  INSERT INTO min_memory_day SELECT min(creation_date) FROM tracks_in_memory;
  BEGIN
  row_count = 1;
  START TRANSACTION;
  WHILE row_count > 0 LOOP
    DELETE FROM tracks_in_memory 
    WHERE creation_date = (select min_date from min_memory_day limit 1)
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
WHERE version_num = 1;


CREATE DATABASE IF NOT EXISTS reid_db PARTITIONS 16;
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
  `poi_id` VARCHAR(36) NOT NULL,
  `detection_type` tinyint(4) NOT NULL,
  `is_ignored` BOOLEAN NOT NULL,
  `feature_id` VARCHAR(36) NOT NULL,
  `features` varbinary(2048) DEFAULT NULL,
  KEY `pk_poi` (poi_id, detection_type, feature_id)
);

/*
call save_poi('[{"is_ignored": false, "poi_id": "P_UUID","detection_type": 1,"groups": ["GROUPAID","GROUPCID","GROUPBID"], "features_data": [{"feature_id": "F_UUID", "features":[0.324234,0.23432423,0.324234,0.2345]}]},{"is_ignored": true, "poi_id": "P_UUID2","detection_type": 1,"groups": ["GROUPAID","GROUPCID","GROUPBID"], "features_data": [{"feature_id": "F_UUID","source_id": "S_UUID", "features":[0.324234,0.23432423,0.324234,0.2345]}]}]');
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
	current_is_ignored BOOLEAN;
   	err_msg VARCHAR(512) = '';
BEGIN
  DROP TABLE IF EXISTS save_poi_result;
  CREATE TEMPORARY TABLE save_poi_result(poi_id VARCHAR(36),is_success VARCHAR(10),error_msg VARCHAR(512));
  FOR i IN 0 .. (array_length-1) LOOP
		BEGIN
			current_json = JSON_EXTRACT_JSON(_array_of_tracks,i);
			current_poi_id = current_json::$poi_id;
                        current_detection_type = current_json::%detection_type;
			current_is_ignored = current_json::is_ignored;
			current_features_data = current_json::features_data;
                        array_features_data_length = JSON_LENGTH(current_features_data);
		        START TRANSACTION;
		        # clean exists
                        DELETE FROM poi
                        WHERE poi_id = current_poi_id;
                # Insert new
                FOR z IN 0 .. (array_features_data_length-1) LOOP
					current_feature_data = JSON_EXTRACT_JSON(current_features_data,z);
					INSERT INTO poi
					(poi_id, detection_type, is_ignored, feature_id, features) VALUES (
					current_poi_id,
                                        current_detection_type,
                                        current_is_ignored,
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
  arr = COLLECT(CONCAT("SELECT hex(features) FROM poi WHERE poi_id = '",_poi_id,"'"), QUERY(features_hex varchar(4096)));
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
                WHERE poi_id = current_poi_id;
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
CREATE OR REPLACE PROCEDURE add_features_to_poi(_poi_id varchar(36), _is_ignored boolean, _detection_type tinyint, _array_of_features json) 
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
							(poi_id, detection_type, is_ignored, feature_id, features) VALUES (
							_poi_id,
							_detection_type,
							_is_ignored,
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
            WHERE poi_id = _poi_id
            AND feature_id = current_feature_data_id;
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


#update finishe of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 1;
