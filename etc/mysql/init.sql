-- VoIP数据库初始化脚本
-- 创建Kamailio所需的基本表

USE voip;

-- 用户位置表 (usrloc)
CREATE TABLE IF NOT EXISTS location (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ruid VARCHAR(64) NOT NULL DEFAULT '',
    username VARCHAR(64) NOT NULL DEFAULT '',
    domain VARCHAR(64) DEFAULT NULL,
    contact VARCHAR(512) NOT NULL DEFAULT '',
    received VARCHAR(128) DEFAULT NULL,
    path VARCHAR(512) DEFAULT NULL,
    expires DATETIME NOT NULL DEFAULT '2030-05-28 21:32:15',
    q FLOAT(10,2) NOT NULL DEFAULT 1.0,
    callid VARCHAR(255) NOT NULL DEFAULT 'Default-Call-ID',
    cseq INT(11) NOT NULL DEFAULT 1,
    last_modified DATETIME NOT NULL DEFAULT '2000-01-01 00:00:01',
    flags INT(11) NOT NULL DEFAULT 0,
    cflags VARCHAR(255) DEFAULT NULL,
    user_agent VARCHAR(255) NOT NULL DEFAULT '',
    socket VARCHAR(64) DEFAULT NULL,
    methods INT(11) DEFAULT NULL,
    instance VARCHAR(255) DEFAULT NULL,
    reg_id INT(11) NOT NULL DEFAULT 0,
    server_id INT(11) NOT NULL DEFAULT 0,
    connection_id INT(11) NOT NULL DEFAULT 0,
    keepalive INT(11) NOT NULL DEFAULT 0,
    `partition` INT(11) NOT NULL DEFAULT 0,
    UNIQUE KEY ruid_idx (ruid),
    KEY account_contact_idx (username, domain, contact)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 用户表 (subscriber)
CREATE TABLE IF NOT EXISTS subscriber (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL DEFAULT '',
    domain VARCHAR(64) NOT NULL DEFAULT '',
    password VARCHAR(64) NOT NULL DEFAULT '',
    email_address VARCHAR(128) NOT NULL DEFAULT '',
    ha1 VARCHAR(128) NOT NULL DEFAULT '',
    ha1b VARCHAR(128) NOT NULL DEFAULT '',
    rpid VARCHAR(128) DEFAULT NULL,
    UNIQUE KEY account_idx (username, domain),
    KEY username_idx (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 版本表
CREATE TABLE IF NOT EXISTS version (
    table_name VARCHAR(32) NOT NULL,
    table_version INT(10) UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY table_name_idx (table_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 插入版本信息
INSERT IGNORE INTO version (table_name, table_version) VALUES ('location', 9);
INSERT IGNORE INTO version (table_name, table_version) VALUES ('subscriber', 7);

-- 创建测试用户
-- 用户: 100134001@voip.com, 100134002@voip.com
-- 密码: voip
INSERT IGNORE INTO subscriber (username, domain, password, ha1, ha1b)
VALUES ('100134001', 'voip.com', 'voip', MD5('100134001:voip.com:voip'), MD5('100134001@voip.com:voip.com:voip'));

INSERT IGNORE INTO subscriber (username, domain, password, ha1, ha1b)
VALUES ('100134002', 'voip.com', 'voip', MD5('100134002:voip.com:voip'), MD5('100134002@voip.com:voip.com:voip'));

-- 修改voip用户使用mysql_native_password认证（兼容Kamailio的MySQL驱动）
ALTER USER 'voip'@'%' IDENTIFIED WITH mysql_native_password BY 'voip_password';

-- 授权
GRANT ALL PRIVILEGES ON voip.* TO 'voip'@'%';
FLUSH PRIVILEGES;
