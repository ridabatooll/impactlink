-- =============================================
-- IMPACTLINK DATABASE - STORED PROCEDURES
-- Rida Batool - 24k-3110
-- =============================================

-- 1. REGISTER USER
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
    DBMS_OUTPUT.PUT_LINE('User registered successfully!');
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Error: Email already exists!');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 2. GET NGO PROFILE
CREATE OR REPLACE PROCEDURE get_ngo_profile (
    p_ngo_id IN NUMBER
)
AS
    v_name        NGOS.name%TYPE;
    v_cause       NGOS.cause%TYPE;
    v_city        NGOS.city%TYPE;
    v_description NGOS.description%TYPE;
    v_status      NGOS.status%TYPE;
    v_urgency     NGOS.urgency_score%TYPE;
BEGIN
    SELECT name, cause, city, description, status, urgency_score
    INTO v_name, v_cause, v_city, v_description, v_status, v_urgency
    FROM NGOS
    WHERE ngo_id = p_ngo_id;
    DBMS_OUTPUT.PUT_LINE('Name: ' || v_name);
    DBMS_OUTPUT.PUT_LINE('Cause: ' || v_cause);
    DBMS_OUTPUT.PUT_LINE('City: ' || v_city);
    DBMS_OUTPUT.PUT_LINE('Description: ' || v_description);
    DBMS_OUTPUT.PUT_LINE('Status: ' || v_status);
    DBMS_OUTPUT.PUT_LINE('Urgency Score: ' || v_urgency);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO not found!');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- 3. VERIFY NGO
CREATE OR REPLACE PROCEDURE verify_ngo (
    p_ngo_id     IN NUMBER,
    p_action     IN VARCHAR2,
    p_admin_note IN VARCHAR2
)
AS
BEGIN
    UPDATE NGOS 
    SET status = p_action
    WHERE ngo_id = p_ngo_id;
    INSERT INTO VERIFICATION_REQUESTS (req_id, ngo_id, status, admin_note, submitted_at)
    VALUES (verif_seq.NEXTVAL, p_ngo_id, p_action, p_admin_note, SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('NGO ' || p_ngo_id || ' has been ' || p_action);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: NGO not found!');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 4. MATCH DONOR TO NGOS
CREATE OR REPLACE PROCEDURE match_donor_to_ngos (
    p_donor_id IN NUMBER
)
AS
    v_cause  DONORS.cause_preference%TYPE;
    v_city   DONORS.city%TYPE;
BEGIN
    SELECT cause_preference, city
    INTO v_cause, v_city
    FROM DONORS
    WHERE donor_id = p_donor_id;
    FOR ngo IN (
        SELECT ngo_id, name, cause, city, urgency_score,
            (CASE WHEN cause = v_cause THEN 40 ELSE 0 END +
             CASE WHEN city = v_city THEN 30 ELSE 0 END +
             urgency_score * 0.3) AS match_score
        FROM NGOS
        WHERE status = 'verified'
        ORDER BY match_score DESC
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'NGO: ' || ngo.name || 
            ' | Cause: ' || ngo.cause || 
            ' | City: ' || ngo.city || 
            ' | Score: ' || ngo.match_score
        );
    END LOOP;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: Donor not found!');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- 5. MAKE DONATION
CREATE OR REPLACE PROCEDURE make_donation (
    p_donor_id IN NUMBER,
    p_ngo_id   IN NUMBER,
    p_amount   IN NUMBER
)
AS
BEGIN
    INSERT INTO DONATIONS (donation_id, donor_id, ngo_id, amount, donated_at)
    VALUES (donations_seq.NEXTVAL, p_donor_id, p_ngo_id, p_amount, SYSDATE);
    INSERT INTO NOTIFICATIONS (notif_id, user_id, message, is_read, created_at)
    SELECT notif_seq.NEXTVAL, u.user_id,
           'Your donation of ' || p_amount || ' PKR to ' || n.name || ' was successful!',
           0, SYSDATE
    FROM DONORS d
    JOIN USERS u ON d.user_id = u.user_id
    JOIN NGOS n ON n.ngo_id = p_ngo_id
    WHERE d.donor_id = p_donor_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Donation successful!');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 6. SEND NOTIFICATION
CREATE OR REPLACE PROCEDURE send_notification (
    p_user_id IN NUMBER,
    p_message IN VARCHAR2
)
AS
BEGIN
    INSERT INTO NOTIFICATIONS (notif_id, user_id, message, is_read, created_at)
    VALUES (notif_seq.NEXTVAL, p_user_id, p_message, 0, SYSDATE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Notification sent successfully!');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 7. ANALYTICS
CREATE OR REPLACE PROCEDURE get_analytics
AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== DONATION ANALYTICS ===');
    FOR rec IN (
        SELECT n.cause,
               COUNT(*) AS total_donations,
               SUM(d.amount) AS total_amount
        FROM DONATIONS d
        JOIN NGOS n ON d.ngo_id = n.ngo_id
        GROUP BY n.cause
    )
    LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Cause: ' || rec.cause ||
            ' | Total Donations: ' || rec.total_donations ||
            ' | Total Amount: ' || rec.total_amount || ' PKR'
        );
    END LOOP;
END;
/