CREATE DATABASE IF NOT EXISTS insight_db PARTITIONS 16;
USE insight_db;

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
INSERT INTO db_schema_version (row_guid,version_num,version_str,deploy_start) VALUES (get_guid(),1,'19.02.18',NOW());

DELIMITER // 
CREATE OR REPLACE PROCEDURE insert_error_row(_procedure_name VARCHAR(256),_error_msg VARCHAR(512))
AS 
BEGIN
    INSERT INTO db_errors_msg_log (row_guid,procedure_name,error_msg)
    SELECT get_guid() as row_guid,_procedure_name,_error_msg;
END // 
DELIMITER ;


CREATE TABLE IF NOT EXISTS `heatmaps` (
  `detection_id` VARCHAR(36) NOT NULL,
  `source_id` VARCHAR(36) NOT NULL,
  `detection_type` TINYINT(4) NOT NULL,
  `detection_date` AS DATE(detection_ts) PERSISTED DATE,
  `detection_ts` DATETIME NOT NULL,
  `is_ignored` BOOLEAN NOT NULL DEFAULT 0,
  `gender` ENUM('male', 'female', 'other', 'unknown', '') NOT NULL DEFAULT '',
  `age_category` ENUM('child', 'teenager', 'adult', 'senior', 'unknown', '') NOT NULL DEFAULT '',
  `classification` ENUM('customer', 'vip customer', 'employee', 'manager', 'unknown', '') NOT NULL DEFAULT '',
  `heatmap` MEDIUMBLOB NOT NULL,
  SHARD KEY `s_heatmaps` (detection_date,source_id),
  PRIMARY KEY `pk_heatmaps` (detection_id,detection_date,source_id)
);

CREATE TABLE IF NOT EXISTS `visits` (
  `visit_id` VARCHAR(36) NOT NULL,
  `customer_id` VARCHAR(36),
  `entrance_date` AS DATE(entrance_ts) PERSISTED DATE,
  `entrance_ts` DATETIME NOT NULL,
  `duration_sec` INT NOT NULL,
  `zones_visited` JSON NOT NULL,
  `is_ignored` BOOLEAN NOT NULL DEFAULT 0,
  `gender` ENUM('male', 'female', 'other', 'unknown', '') NOT NULL DEFAULT '',
  `age_category` ENUM('child', 'teenager', 'adult', 'senior', 'unknown', '') NOT NULL DEFAULT '',
  `classification` ENUM('customer', 'vip customer', 'employee', 'manager', 'unknown', '') NOT NULL DEFAULT '',
  SHARD KEY `s_visits` (entrance_date),
  PRIMARY KEY `pk_visits` (visit_id,entrance_date)
);


#update finishe of first version
UPDATE db_schema_version 
SET deploy_end = NOW(),
is_success = 'true'
WHERE version_num = 1;
