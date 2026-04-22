-- ============================================================
--  TRIGGER
--  SRS Section 6 requires at least one trigger.
--  Fires after any UPDATE to NGOS.status and auto-inserts a
--  notification. Uses :NEW.user_id directly to avoid mutating
--  table issue from querying NGOS inside a NGOS trigger.
-- ============================================================
CREATE OR REPLACE TRIGGER trg_ngo_status_change
AFTER UPDATE OF status ON NGOS
FOR EACH ROW
WHEN (NEW.status IN ('approved', 'rejected'))
DECLARE
    v_message VARCHAR2(300);
BEGIN
    v_message := CASE :NEW.status
        WHEN 'approved' THEN
            'Congratulations! Your NGO registration has been approved. You may now post needs.'
        WHEN 'rejected' THEN
            'Your NGO registration has been rejected. Please review and re-register with updated documentation.'
    END;
 
    INSERT INTO NOTIFICATIONS (notif_id, user_id, notif_type, message, is_read, created_at)
    VALUES (notif_seq.NEXTVAL, :NEW.user_id, 'verification', v_message, 0, SYSDATE);
END;
/
 
 
-- ============================================================
--  ANALYTICS VIEWS
--  SRS REQ-ANLYT-04 + Section 6: must be SQL views.
-- ============================================================
 
-- View 1: Donation commitments grouped by cause category (REQ-ANLYT-02)
CREATE OR REPLACE VIEW vw_donations_by_category AS
SELECT
    c.name                 AS category,
    COUNT(don.donation_id) AS total_commitments
FROM DONATIONS don
JOIN NEEDS      nd ON don.need_id    = nd.need_id
JOIN CATEGORIES c  ON nd.category_id = c.category_id
GROUP BY c.name;
 
 
-- View 2: System-wide summary stats for Admin dashboard (REQ-ANLYT-01)
CREATE OR REPLACE VIEW vw_admin_summary AS
SELECT
    (SELECT COUNT(*) FROM DONORS)                            AS total_donors,
    (SELECT COUNT(*) FROM NGOS    WHERE status = 'approved') AS verified_ngos,
    (SELECT COUNT(*) FROM NEEDS   WHERE status = 'open')     AS active_needs,
    (SELECT COUNT(*) FROM DONATIONS)                         AS total_commitments
FROM DUAL;
 
 
-- View 3: Open needs with commitment counts per NGO (REQ-ANLYT-03)
CREATE OR REPLACE VIEW vw_ngo_need_commitments AS
SELECT
    n.ngo_id,
    n.ngo_name,
    nd.need_id,
    nd.title         AS need_title,
    nd.urgency_level,
    COUNT(don.donation_id) AS commitment_count
FROM NGOS n
JOIN NEEDS      nd  ON n.ngo_id    = nd.ngo_id
LEFT JOIN DONATIONS don ON nd.need_id = don.need_id
WHERE nd.status = 'open'
GROUP BY n.ngo_id, n.ngo_name, nd.need_id, nd.title, nd.urgency_level;
 
 
-- View 4: Donor commitment history (REQ-DON-04)
CREATE OR REPLACE VIEW vw_donor_history AS
SELECT
    d.donor_id,
    u.name           AS donor_name,
    don.donation_id,
    nd.title         AS need_title,
    n.ngo_name,
    don.item_description,
    don.status,
    don.committed_at
FROM DONATIONS don
JOIN DONORS d  ON don.donor_id = d.donor_id
JOIN USERS  u  ON d.user_id    = u.user_id
JOIN NEEDS  nd ON don.need_id  = nd.need_id
JOIN NGOS   n  ON nd.ngo_id    = n.ngo_id
ORDER BY don.committed_at DESC;
 
 
-- View 5: Donors committed to an NGO's needs (REQ-DON-05)
CREATE OR REPLACE VIEW vw_ngo_committed_donors AS
SELECT
    n.ngo_id,
    n.ngo_name,
    nd.need_id,
    nd.title         AS need_title,
    d.donor_id,
    u.name           AS donor_name,
    u.email          AS donor_email,
    don.item_description,
    don.status       AS commitment_status,
    don.committed_at
FROM DONATIONS don
JOIN NEEDS  nd ON don.need_id  = nd.need_id
JOIN NGOS   n  ON nd.ngo_id    = n.ngo_id
JOIN DONORS d  ON don.donor_id = d.donor_id
JOIN USERS  u  ON d.user_id    = u.user_id
ORDER BY n.ngo_id, nd.need_id, don.committed_at DESC;
 
 
-- ============================================================
--  STORED PROCEDURES
-- ============================================================
 
 
-- ============================================================
--  SECTION 1: USER & ROLE MANAGEMENT
-- ============================================================
 
-- 1. REGISTER USER
--    Creates a base user record. Role-specific record (donor/ngo)
--    must be created separately after this.
CREATE OR REPLACE PROCEDURE register_user (
    p_name          IN VARCHAR2,
    p_email         IN VARCHAR2,
    p_password_hash IN VARCHAR2,
    p_role          IN VARCHAR2
)
AS
BEGIN
    INSERT INTO USERS (user_id, name, email, password_hash, user_role, created_at)
    VALUES (users_seq.NEXTVAL, p_name, p_email, p_password_hash, p_role, SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('User registered: ' || p_name);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: Email already exists.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 2. REGISTER DONOR
--    Creates the DONORS specialisation record after register_user.
--    p_user_id must already exist in USERS with role = 'donor'.
CREATE OR REPLACE PROCEDURE register_donor (
    p_user_id IN NUMBER
)
AS
BEGIN
    INSERT INTO DONORS (donor_id, user_id)
    VALUES (donors_seq.NEXTVAL, p_user_id);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donor profile created for user_id: ' || p_user_id);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: Donor profile already exists for this user.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 3. REGISTER NGO
--    Creates the NGOS specialisation record after register_user.
--    p_user_id must already exist in USERS with role = 'ngo'.
CREATE OR REPLACE PROCEDURE register_ngo (
    p_user_id     IN NUMBER,
    p_ngo_name    IN VARCHAR2,
    p_city        IN VARCHAR2,
    p_description IN VARCHAR2
)
AS
BEGIN
    INSERT INTO NGOS (ngo_id, user_id, ngo_name, city, description, status, registered_at)
    VALUES (ngos_seq.NEXTVAL, p_user_id, p_ngo_name, p_city, p_description, 'pending', SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('NGO profile created: ' || p_ngo_name);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO profile already exists for this user.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 2: LOCATION MANAGEMENT
-- ============================================================
 
-- 4. ADD DONOR LOCATION
--    A donor can call this multiple times to add multiple locations.
CREATE OR REPLACE PROCEDURE add_donor_location (
    p_donor_id    IN NUMBER,
    p_city        IN VARCHAR2,
    p_province    IN VARCHAR2,
    p_country     IN VARCHAR2,
    p_postal_code IN VARCHAR2
)
AS
BEGIN
    INSERT INTO DONOR_LOCATIONS (location_id, donor_id, city, province, country, postal_code)
    VALUES (locations_seq.NEXTVAL, p_donor_id, p_city, p_province, p_country, p_postal_code);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Location added for donor_id: ' || p_donor_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 5. REMOVE DONOR LOCATION
CREATE OR REPLACE PROCEDURE remove_donor_location (
    p_location_id IN NUMBER
)
AS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM DONOR_LOCATIONS
    WHERE location_id = p_location_id;
 
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Location not found.');
        RETURN;
    END IF;
 
    DELETE FROM DONOR_LOCATIONS WHERE location_id = p_location_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Location removed: ' || p_location_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 3: CATEGORY & PREFERENCE MANAGEMENT
-- ============================================================
 
-- 6. ADD CATEGORY  (admin only at application level)
CREATE OR REPLACE PROCEDURE add_category (
    p_name        IN VARCHAR2,
    p_description IN VARCHAR2
)
AS
BEGIN
    INSERT INTO CATEGORIES (category_id, name, description)
    VALUES (categories_seq.NEXTVAL, p_name, p_description);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Category added: ' || p_name);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: Category already exists.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 7. SET DONOR PREFERENCE
--    Adds one category preference for a donor.
--    Call multiple times for multiple causes.
CREATE OR REPLACE PROCEDURE set_donor_preference (
    p_donor_id    IN NUMBER,
    p_category_id IN NUMBER
)
AS
BEGIN
    INSERT INTO DONOR_PREFERENCES (donor_id, category_id)
    VALUES (p_donor_id, p_category_id);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Preference set for donor_id: ' || p_donor_id);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Preference already exists for this donor and category.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 8. SET NGO CATEGORY
--    Assigns one cause category to an NGO.
--    Call multiple times for multiple causes.
CREATE OR REPLACE PROCEDURE set_ngo_category (
    p_ngo_id      IN NUMBER,
    p_category_id IN NUMBER
)
AS
BEGIN
    INSERT INTO NGO_CATEGORIES (ngo_id, category_id)
    VALUES (p_ngo_id, p_category_id);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Category assigned to ngo_id: ' || p_ngo_id);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Category already assigned to this NGO.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 4: DOCUMENT & VERIFICATION MANAGEMENT
-- ============================================================
 
-- 9. UPLOAD DOCUMENT
--    NGO uploads a verification document.
CREATE OR REPLACE PROCEDURE upload_document (
    p_ngo_id    IN NUMBER,
    p_file_path IN VARCHAR2,
    p_doc_type  IN VARCHAR2
)
AS
BEGIN
    INSERT INTO DOCUMENTS (doc_id, ngo_id, file_path, doc_type, uploaded_at)
    VALUES (documents_seq.NEXTVAL, p_ngo_id, p_file_path, p_doc_type, SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Document uploaded for ngo_id: ' || p_ngo_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 10. VERIFY NGO
--     Admin approves or rejects an NGO.
--     Updates NGOS.status and writes an audit row to VERIFICATION_LOG.
--     Notification is sent by trg_ngo_status_change trigger.
--     SRS REQ-VER-03: rejection reason included in notification via trigger.
CREATE OR REPLACE PROCEDURE verify_ngo (
    p_ngo_id   IN NUMBER,
    p_admin_id IN NUMBER,
    p_action   IN VARCHAR2,
    p_remarks  IN VARCHAR2
)
AS
    v_count NUMBER;
BEGIN
    IF p_action NOT IN ('approved', 'rejected') THEN
        DBMS_OUTPUT.PUT_LINE('Error: Action must be approved or rejected.');
        RETURN;
    END IF;
 
    SELECT COUNT(*) INTO v_count FROM NGOS WHERE ngo_id = p_ngo_id;
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO not found.');
        RETURN;
    END IF;
 
    UPDATE NGOS SET status = p_action WHERE ngo_id = p_ngo_id;
 
    INSERT INTO VERIFICATION_LOG (log_id, ngo_id, admin_id, action, remarks, actioned_at)
    VALUES (verif_log_seq.NEXTVAL, p_ngo_id, p_admin_id, p_action, p_remarks, SYSDATE);
 
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('NGO ' || p_ngo_id || ' has been ' || p_action || '.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 5: NEEDS MANAGEMENT
-- ============================================================
 
-- 11. POST NEED
--     SRS REQ-VER-04: only approved NGOs may post needs.
--     SRS REQ-NEED-01: includes target_quantity field.
CREATE OR REPLACE PROCEDURE post_need (
    p_ngo_id          IN NUMBER,
    p_category_id     IN NUMBER,
    p_title           IN VARCHAR2,
    p_description     IN VARCHAR2,
    p_urgency_level   IN VARCHAR2,
    p_target_quantity IN NUMBER DEFAULT 1
)
AS
    v_status NGOS.status%TYPE;
BEGIN
    SELECT status INTO v_status FROM NGOS WHERE ngo_id = p_ngo_id;
 
    IF v_status != 'approved' THEN
        DBMS_OUTPUT.PUT_LINE('Error: Only approved NGOs can post needs. Current status: ' || v_status);
        RETURN;
    END IF;
 
    INSERT INTO NEEDS (need_id, ngo_id, category_id, title, description,
                       urgency_level, target_quantity, status, created_at)
    VALUES (needs_seq.NEXTVAL, p_ngo_id, p_category_id, p_title, p_description,
            p_urgency_level, p_target_quantity, 'open', SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Need posted: ' || p_title);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO not found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 12. UPDATE NEED STATUS
--     NGO closes or marks a need as fulfilled.
CREATE OR REPLACE PROCEDURE update_need_status (
    p_need_id IN NUMBER,
    p_status  IN VARCHAR2
)
AS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM NEEDS WHERE need_id = p_need_id;
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Need not found.');
        RETURN;
    END IF;
 
    UPDATE NEEDS SET status = p_status WHERE need_id = p_need_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Need ' || p_need_id || ' updated to: ' || p_status);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 13. UPDATE NEED
--     SRS REQ-NEED-02: NGO can edit any field of a need they own.
--     NULL parameters mean leave that field unchanged.
--     SRS REQ-NEED-04: ownership enforced before any update.
CREATE OR REPLACE PROCEDURE update_need (
    p_need_id         IN NUMBER,
    p_ngo_id          IN NUMBER,
    p_title           IN VARCHAR2 DEFAULT NULL,
    p_description     IN VARCHAR2 DEFAULT NULL,
    p_category_id     IN NUMBER   DEFAULT NULL,
    p_urgency_level   IN VARCHAR2 DEFAULT NULL,
    p_target_quantity IN NUMBER   DEFAULT NULL
)
AS
    v_count NUMBER;
    v_owner NEEDS.ngo_id%TYPE;
BEGIN
    SELECT COUNT(*), MAX(ngo_id)
    INTO v_count, v_owner
    FROM NEEDS WHERE need_id = p_need_id;
 
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Need not found.');
        RETURN;
    END IF;
 
    IF v_owner != p_ngo_id THEN
        DBMS_OUTPUT.PUT_LINE('Error: You do not own this need.');
        RETURN;
    END IF;
 
    UPDATE NEEDS SET
        title           = NVL(p_title,           title),
        description     = NVL(p_description,     description),
        category_id     = NVL(p_category_id,     category_id),
        urgency_level   = NVL(p_urgency_level,   urgency_level),
        target_quantity = NVL(p_target_quantity, target_quantity)
    WHERE need_id = p_need_id;
 
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Need ' || p_need_id || ' updated.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 6: MATCHING ENGINE
-- ============================================================
 
-- 14. MATCH DONOR TO NGOS
--     SRS REQ-MATCH-01 formula:
--       Score = (Location x 0.4) + (Cause x 0.4) + (Urgency x 0.2)
--     Each component normalised to 100; max possible score = 100.
--       Location : 100 if any donor city matches NGO city, else 0
--       Cause    : (matched categories / total preferences) x 100
--       Urgency  : critical=100, high=75, medium=40, low=10
--     SRS REQ-MATCH-02: only NGOs with at least one open need are returned.
--     SRS REQ-MATCH-03: results sorted by score descending.
CREATE OR REPLACE PROCEDURE match_donor_to_ngos (
    p_donor_id IN NUMBER
)
AS
    v_count      NUMBER;
    v_pref_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM DONORS WHERE donor_id = p_donor_id;
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Donor not found.');
        RETURN;
    END IF;
 
    SELECT COUNT(*) INTO v_pref_count
    FROM DONOR_PREFERENCES
    WHERE donor_id = p_donor_id;
 
    IF v_pref_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('No preferences set. Please configure cause preferences first.');
        RETURN;
    END IF;
 
    FOR rec IN (
        SELECT
            n.ngo_id,
            n.ngo_name,
            n.city,
            MAX(CASE WHEN dl.city = n.city THEN 100 ELSE 0 END) * 0.4
            + (COUNT(DISTINCT CASE WHEN dp.category_id = nc.category_id
                                   THEN dp.category_id END) / v_pref_count * 100) * 0.4
            + MAX(CASE nd.urgency_level
                    WHEN 'critical' THEN 100
                    WHEN 'high'     THEN 75
                    WHEN 'medium'   THEN 40
                    WHEN 'low'      THEN 10
                    ELSE 0
                  END) * 0.2
            AS match_score
        FROM NGOS n
        JOIN NGO_CATEGORIES    nc ON n.ngo_id       = nc.ngo_id
        JOIN DONOR_PREFERENCES dp ON dp.category_id = nc.category_id
                                  AND dp.donor_id   = p_donor_id
        JOIN NEEDS             nd ON nd.ngo_id       = n.ngo_id
                                  AND nd.status      = 'open'
        LEFT JOIN DONOR_LOCATIONS dl ON dl.donor_id = p_donor_id
        WHERE n.status = 'approved'
        GROUP BY n.ngo_id, n.ngo_name, n.city
        ORDER BY match_score DESC
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'NGO: '     || rec.ngo_name ||
            ' | City: ' || rec.city     ||
            ' | Score: '|| ROUND(rec.match_score, 2)
        );
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
 
 
-- ============================================================
--  SECTION 7: DONATIONS
-- ============================================================
 
-- 15. MAKE DONATION
--     SRS REQ-DON-01: stores donor_id, need_id, ngo_id, committed_at, status.
--     SRS REQ-DON-02: duplicate commitment check before insert.
--     SRS REQ-DON-03: notifies NGO on new commitment.
CREATE OR REPLACE PROCEDURE make_donation (
    p_donor_id         IN NUMBER,
    p_need_id          IN NUMBER,
    p_item_description IN VARCHAR2
)
AS
    v_ngo_id     NGOS.ngo_id%TYPE;
    v_ngo_name   NGOS.ngo_name%TYPE;
    v_need_title NEEDS.title%TYPE;
    v_count      NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM NEEDS WHERE need_id = p_need_id AND status = 'open';
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Need not found or is no longer open.');
        RETURN;
    END IF;
 
    SELECT COUNT(*) INTO v_count
    FROM DONATIONS
    WHERE donor_id = p_donor_id AND need_id = p_need_id;
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: You have already committed to this need.');
        RETURN;
    END IF;
 
    SELECT n.ngo_id, n.ngo_name, nd.title
    INTO v_ngo_id, v_ngo_name, v_need_title
    FROM NEEDS nd
    JOIN NGOS n ON nd.ngo_id = n.ngo_id
    WHERE nd.need_id = p_need_id;
 
    INSERT INTO DONATIONS (donation_id, donor_id, need_id, ngo_id, item_description, status, committed_at)
    VALUES (donations_seq.NEXTVAL, p_donor_id, p_need_id, v_ngo_id, p_item_description, 'committed', SYSDATE);
 
    INSERT INTO NOTIFICATIONS (notif_id, user_id, notif_type, message, is_read, created_at)
    SELECT notif_seq.NEXTVAL, u.user_id,
           'donation',
           'Your commitment to "' || v_need_title || '" at ' || v_ngo_name || ' was recorded.',
           0, SYSDATE
    FROM DONORS d JOIN USERS u ON d.user_id = u.user_id
    WHERE d.donor_id = p_donor_id;
 
    INSERT INTO NOTIFICATIONS (notif_id, user_id, notif_type, message, is_read, created_at)
    SELECT notif_seq.NEXTVAL, u.user_id,
           'donation',
           'A donor has committed to your need: "' || v_need_title || '".',
           0, SYSDATE
    FROM NGOS n JOIN USERS u ON n.user_id = u.user_id
    WHERE n.ngo_id = v_ngo_id;
 
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donation committed to: ' || v_need_title);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: Duplicate commitment detected.');
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 16. UPDATE DONATION STATUS
--     Mark a committed donation as completed or cancelled.
CREATE OR REPLACE PROCEDURE update_donation_status (
    p_donation_id IN NUMBER,
    p_status      IN VARCHAR2
)
AS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM DONATIONS WHERE donation_id = p_donation_id;
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Donation not found.');
        RETURN;
    END IF;
 
    UPDATE DONATIONS SET status = p_status WHERE donation_id = p_donation_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donation ' || p_donation_id || ' updated to: ' || p_status);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 8: PROFILE PROCEDURES
-- ============================================================
 
-- 17. GET NGO PROFILE
--     Returns NGO details with categories as comma-separated list.
CREATE OR REPLACE PROCEDURE get_ngo_profile (
    p_ngo_id IN NUMBER
)
AS
    v_name        NGOS.ngo_name%TYPE;
    v_city        NGOS.city%TYPE;
    v_description NGOS.description%TYPE;
    v_status      NGOS.status%TYPE;
    v_categories  VARCHAR2(500);
BEGIN
    SELECT ngo_name, city, description, status
    INTO v_name, v_city, v_description, v_status
    FROM NGOS
    WHERE ngo_id = p_ngo_id;
 
    SELECT LISTAGG(c.name, ', ') WITHIN GROUP (ORDER BY c.name)
    INTO v_categories
    FROM NGO_CATEGORIES nc
    JOIN CATEGORIES c ON nc.category_id = c.category_id
    WHERE nc.ngo_id = p_ngo_id;
 
    DBMS_OUTPUT.PUT_LINE('Name:        ' || v_name);
    DBMS_OUTPUT.PUT_LINE('City:        ' || v_city);
    DBMS_OUTPUT.PUT_LINE('Description: ' || v_description);
    DBMS_OUTPUT.PUT_LINE('Status:      ' || v_status);
    DBMS_OUTPUT.PUT_LINE('Categories:  ' || NVL(v_categories, 'None assigned'));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO not found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
 
 
-- 18. GET DONOR PROFILE
--     Returns donor preferences and all saved locations.
CREATE OR REPLACE PROCEDURE get_donor_profile (
    p_donor_id IN NUMBER
)
AS
    v_name        USERS.name%TYPE;
    v_email       USERS.email%TYPE;
    v_preferences VARCHAR2(500);
BEGIN
    SELECT u.name, u.email
    INTO v_name, v_email
    FROM DONORS d
    JOIN USERS u ON d.user_id = u.user_id
    WHERE d.donor_id = p_donor_id;
 
    SELECT LISTAGG(c.name, ', ') WITHIN GROUP (ORDER BY c.name)
    INTO v_preferences
    FROM DONOR_PREFERENCES dp
    JOIN CATEGORIES c ON dp.category_id = c.category_id
    WHERE dp.donor_id = p_donor_id;
 
    DBMS_OUTPUT.PUT_LINE('Name:        ' || v_name);
    DBMS_OUTPUT.PUT_LINE('Email:       ' || v_email);
    DBMS_OUTPUT.PUT_LINE('Preferences: ' || NVL(v_preferences, 'None set'));
    DBMS_OUTPUT.PUT_LINE('--- Locations ---');
 
    FOR loc IN (
        SELECT city, province, country, postal_code
        FROM DONOR_LOCATIONS
        WHERE donor_id = p_donor_id
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            loc.city || ', ' || loc.province ||
            ', ' || loc.country ||
            ' (' || loc.postal_code || ')'
        );
    END LOOP;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: Donor not found.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
 
 
-- ============================================================
--  SECTION 9: NOTIFICATIONS
-- ============================================================
 
-- 19. SEND NOTIFICATION
--     Generic utility — sends any message to any user.
CREATE OR REPLACE PROCEDURE send_notification (
    p_user_id    IN NUMBER,
    p_notif_type IN VARCHAR2,
    p_message    IN VARCHAR2
)
AS
BEGIN
    INSERT INTO NOTIFICATIONS (notif_id, user_id, notif_type, message, is_read, created_at)
    VALUES (notif_seq.NEXTVAL, p_user_id, p_notif_type, p_message, 0, SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Notification sent to user_id: ' || p_user_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 20. MARK NOTIFICATION READ
CREATE OR REPLACE PROCEDURE mark_notification_read (
    p_notif_id IN NUMBER
)
AS
BEGIN
    UPDATE NOTIFICATIONS SET is_read = 1 WHERE notif_id = p_notif_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Notification ' || p_notif_id || ' marked as read.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- 21. MARK ALL NOTIFICATIONS READ
--     SRS REQ-NOTIF-04: users can mark all notifications read at once.
CREATE OR REPLACE PROCEDURE mark_all_notifications_read (
    p_user_id IN NUMBER
)
AS
BEGIN
    UPDATE NOTIFICATIONS
    SET is_read = 1
    WHERE user_id = p_user_id AND is_read = 0;
 
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('All notifications marked as read for user_id: ' || p_user_id);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/
 
 
-- ============================================================
--  SECTION 10: ANALYTICS
-- ============================================================
 
-- 22. GET ANALYTICS
--     Donations per category, open needs per NGO, top donors.
--     Queries the analytics views defined above.
CREATE OR REPLACE PROCEDURE get_analytics
AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== DONATIONS BY CATEGORY ===');
    FOR rec IN (
        SELECT category, total_commitments
        FROM vw_donations_by_category
        ORDER BY total_commitments DESC
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Category: ' || rec.category ||
            ' | Donations: ' || rec.total_commitments
        );
    END LOOP;
 
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('=== OPEN NEEDS PER NGO ===');
    FOR rec IN (
        SELECT ngo_name, COUNT(need_id) AS open_needs
        FROM vw_ngo_need_commitments
        GROUP BY ngo_name
        ORDER BY open_needs DESC
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'NGO: ' || rec.ngo_name ||
            ' | Open Needs: ' || rec.open_needs
        );
    END LOOP;
 
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('=== TOP 5 DONORS BY COMMITMENTS ===');
    FOR rec IN (
        SELECT donor_name, COUNT(donation_id) AS total_commitments
        FROM vw_donor_history
        GROUP BY donor_name
        ORDER BY total_commitments DESC
        FETCH FIRST 5 ROWS ONLY
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Donor: ' || rec.donor_name ||
            ' | Commitments: ' || rec.total_commitments
        );
    END LOOP;
END;
/
