const { getConnection } = require('./db/connection');

async function test() {
    const conn = await getConnection();
    const result = await conn.execute(
        `SELECT table_name FROM user_tables 
         WHERE table_name IN ('USERS','DONORS','NGOS','VERIFICATION_REQUESTS','MATCHES','DONATIONS','NOTIFICATIONS')
         ORDER BY table_name`
    );
    console.log("ImpactLink tables:", result.rows);
    await conn.close();
}

test();