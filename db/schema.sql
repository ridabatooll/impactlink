-- ============================================================
--  ImpactLink Database Schema  |  Oracle XE
--  All sequences use START WITH 1 INCREMENT BY 1
--  Insertion order matters: parent tables before children
-- ============================================================
 
 
-- ------------------------------------------------------------
--  1. USERS  (generalised entity for all roles)
-- ------------------------------------------------------------
CREATE TABLE USERS (
    user_id       NUMBER          PRIMARY KEY,
    name          VARCHAR2(100)   NOT NULL,
    email         VARCHAR2(100)   UNIQUE NOT NULL,
    password_hash VARCHAR2(255)   NOT NULL,
    user_role     VARCHAR2(10)    NOT NULL
                  CHECK (user_role IN ('donor', 'ngo', 'admin')),
    created_at    DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  2. DONORS  (specialisation of USERS, 1:1)
-- ------------------------------------------------------------
-- No city/cause/urgency columns on DONORS.
-- Locations live in DONOR_LOCATIONS (1:N).
-- Preferences live in DONOR_PREFERENCES (M:N with CATEGORIES).
CREATE TABLE DONORS (
    donor_id          NUMBER        PRIMARY KEY,
    user_id           NUMBER        NOT NULL UNIQUE
                      REFERENCES USERS(user_id)
);
CREATE SEQUENCE donors_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  2b. DONOR_LOCATIONS  (weak entity — depends on DONORS, 1:N)
--      One donor can register multiple preferred locations.
-- ------------------------------------------------------------
CREATE TABLE DONOR_LOCATIONS (
    location_id   NUMBER          PRIMARY KEY,
    donor_id      NUMBER          NOT NULL
                  REFERENCES DONORS(donor_id),
    city          VARCHAR2(100),
    province      VARCHAR2(100),
    country       VARCHAR2(100),
    postal_code   VARCHAR2(20)
);
CREATE SEQUENCE locations_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  3. NGOS  (specialisation of USERS, 1:1)
-- ------------------------------------------------------------
-- No cause column here.
-- Categories live in NGO_CATEGORIES (M:N with CATEGORIES).
CREATE TABLE NGOS (
    ngo_id        NUMBER          PRIMARY KEY,
    user_id       NUMBER          NOT NULL UNIQUE
                  REFERENCES USERS(user_id),
    ngo_name      VARCHAR2(150)   NOT NULL,
    city          VARCHAR2(100),
    description   VARCHAR2(500),
    status        VARCHAR2(10)    DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected'))
);
CREATE SEQUENCE ngos_seq START WITH 1 INCREMENT BY 1;
 
-- SRS REQ-VER-05: admin queue must show NGO registration date.
-- USERS.created_at is the account date; this is the NGO
-- application submission date — they can differ if re-applying.
ALTER TABLE NGOS ADD registered_at DATE DEFAULT SYSDATE;
 
 
-- ------------------------------------------------------------
--  4. CATEGORIES  (lookup table for cause types)
-- ------------------------------------------------------------
CREATE TABLE CATEGORIES (
    category_id   NUMBER          PRIMARY KEY,
    name          VARCHAR2(100)   NOT NULL UNIQUE,
    description   VARCHAR2(300)
);
CREATE SEQUENCE categories_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  5. NGO_CATEGORIES  (M:N bridge: NGOS <-> CATEGORIES)
-- ------------------------------------------------------------
CREATE TABLE NGO_CATEGORIES (
    ngo_id        NUMBER  NOT NULL REFERENCES NGOS(ngo_id),
    category_id   NUMBER  NOT NULL REFERENCES CATEGORIES(category_id),
    CONSTRAINT pk_ngo_categories PRIMARY KEY (ngo_id, category_id)
);
 
 
-- ------------------------------------------------------------
--  6. DONOR_PREFERENCES  (M:N bridge: DONORS <-> CATEGORIES)
-- ------------------------------------------------------------
CREATE TABLE DONOR_PREFERENCES (
    donor_id      NUMBER  NOT NULL REFERENCES DONORS(donor_id),
    category_id   NUMBER  NOT NULL REFERENCES CATEGORIES(category_id),
    CONSTRAINT pk_donor_preferences PRIMARY KEY (donor_id, category_id)
);
 
 
-- ------------------------------------------------------------
--  7. DOCUMENTS  (weak entity — depends on NGOS)
--     Stores verification documents submitted by NGOs.
-- ------------------------------------------------------------
CREATE TABLE DOCUMENTS (
    doc_id        NUMBER          PRIMARY KEY,
    ngo_id        NUMBER          NOT NULL
                  REFERENCES NGOS(ngo_id),
    file_path     VARCHAR2(500)   NOT NULL,
    doc_type      VARCHAR2(100),
    uploaded_at   DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE documents_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  8. VERIFICATION_LOG  (audit trail — depends on NGOS + USERS)
--     Records every admin approval or rejection action.
-- ------------------------------------------------------------
CREATE TABLE VERIFICATION_LOG (
    log_id        NUMBER          PRIMARY KEY,
    ngo_id        NUMBER          NOT NULL
                  REFERENCES NGOS(ngo_id),
    admin_id      NUMBER          NOT NULL
                  REFERENCES USERS(user_id),
    action        VARCHAR2(10)    NOT NULL
                  CHECK (action IN ('approved', 'rejected')),
    remarks       VARCHAR2(300),
    actioned_at   DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE verif_log_seq START WITH 1 INCREMENT BY 1;
 
 
-- ------------------------------------------------------------
--  9. NEEDS  (posted by NGOs; the unit donors commit to)
--     No city/location column: a need inherits location from its NGO.
-- ------------------------------------------------------------
CREATE TABLE NEEDS (
    need_id       NUMBER          PRIMARY KEY,
    ngo_id        NUMBER          NOT NULL
                  REFERENCES NGOS(ngo_id),
    category_id   NUMBER          NOT NULL
                  REFERENCES CATEGORIES(category_id),
    title         VARCHAR2(200)   NOT NULL,
    description   VARCHAR2(1000),
    urgency_level VARCHAR2(10)    DEFAULT 'medium'
                  CHECK (urgency_level IN ('low', 'medium', 'high')),
    status        VARCHAR2(10)    DEFAULT 'open'
                  CHECK (status IN ('open', 'fulfilled', 'closed')),
    created_at    DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE needs_seq START WITH 1 INCREMENT BY 1;
 
-- SRS REQ-NEED-01: four urgency levels including critical.
ALTER TABLE NEEDS DROP CONSTRAINT chk_urgency;
ALTER TABLE NEEDS ADD CONSTRAINT chk_urgency
    CHECK (urgency_level IN ('low', 'medium', 'high', 'critical'));
 
-- SRS REQ-NEED-01: target quantity is a required field.
ALTER TABLE NEEDS ADD target_quantity NUMBER DEFAULT 1;
 
 
-- ------------------------------------------------------------
-- 10. DONATIONS  (weak entity — depends on DONORS + NEEDS)
--     A donor commits to a specific need, not a generic NGO.
--     No amount column: donations are commitments, not transactions.
-- ------------------------------------------------------------
CREATE TABLE DONATIONS (
    donation_id       NUMBER          PRIMARY KEY,
    donor_id          NUMBER          NOT NULL
                      REFERENCES DONORS(donor_id),
    need_id           NUMBER          NOT NULL
                      REFERENCES NEEDS(need_id),
    item_description  VARCHAR2(300),
    status            VARCHAR2(15)    DEFAULT 'committed'
                      CHECK (status IN ('committed', 'completed', 'cancelled')),
    committed_at      DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE donations_seq START WITH 1 INCREMENT BY 1;
 
-- SRS REQ-DON-01: OrganizationID must be stored on the commitment record.
-- Noted denormalization — ngo_id is derivable via need_id but SRS mandates it.
ALTER TABLE DONATIONS ADD ngo_id NUMBER REFERENCES NGOS(ngo_id);
 
-- SRS REQ-DON-02: a donor cannot commit to the same need twice.
ALTER TABLE DONATIONS ADD CONSTRAINT uq_donor_need
    UNIQUE (donor_id, need_id);
 
 
-- ------------------------------------------------------------
-- 11. NOTIFICATIONS
-- ------------------------------------------------------------
CREATE TABLE NOTIFICATIONS (
    notif_id          NUMBER          PRIMARY KEY,
    user_id           NUMBER          NOT NULL
                      REFERENCES USERS(user_id),
    notif_type        VARCHAR2(50)    NOT NULL,
    message           VARCHAR2(500)   NOT NULL,
    is_read           NUMBER(1)       DEFAULT 0
                      CHECK (is_read IN (0, 1)),
    created_at        DATE            DEFAULT SYSDATE
);
CREATE SEQUENCE notif_seq START WITH 1 INCREMENT BY 1;
 
 
-- ============================================================
--  Verify all tables were created
-- ============================================================
SELECT table_name FROM user_tables ORDER BY table_name;
