
CREATE DATABASE IF NOT EXISTS partner_lead_db;
USE partner_lead_db;

CREATE TABLE IF NOT EXISTS lead_batch (
  batch_id VARCHAR(40) NOT NULL,
  partner_id VARCHAR(20) NOT NULL,
  file_name VARCHAR(200) NOT NULL,
  file_checksum VARCHAR(64) NOT NULL,
  record_count INT NOT NULL,
  created_count INT DEFAULT 0,
  updated_count INT DEFAULT 0,
  skipped_count INT DEFAULT 0,
  rejected_count INT DEFAULT 0,
  failed_count INT DEFAULT 0,
  batch_status VARCHAR(30) NOT NULL,
  correlation_id VARCHAR(50) NOT NULL,
  received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMP DEFAULT NULL,
  PRIMARY KEY (batch_id),
  UNIQUE KEY (file_name, file_checksum)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS lead_sync_status (
  record_seq INT NOT NULL AUTO_INCREMENT,
  batch_id VARCHAR(40) NOT NULL,
  row_number INT NOT NULL,
  lead_ref VARCHAR(40) NOT NULL,
  email VARCHAR(150) DEFAULT NULL,
  company VARCHAR(150) DEFAULT NULL,
  salesforce_id VARCHAR(18) DEFAULT NULL,
  record_status VARCHAR(30) NOT NULL,
  error_code VARCHAR(60) DEFAULT NULL,
  error_message VARCHAR(500) DEFAULT NULL,
  retry_count INT DEFAULT 0,
  correlation_id VARCHAR(50) NOT NULL,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (record_seq),
  UNIQUE KEY (batch_id, lead_ref),
  CONSTRAINT fk_lead_batch
    FOREIGN KEY (batch_id) REFERENCES lead_batch(batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
