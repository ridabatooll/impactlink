const oracledb = require('oracledb');

oracledb.initOracleClient({ libDir: 'C:\\oracle\\instantclient\\instantclient_23_0' });

async function getConnection() {
    try {
        const connection = await oracledb.getConnection({
            user: "system",
            password: "system",
            connectString: "localhost/XE"
        });
        console.log("Connected to Oracle Database!");
        return connection;
    } catch (err) {
        console.error("Database connection error:", err);
        throw err;
    }
}

module.exports = { getConnection };