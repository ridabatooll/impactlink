const express = require('express');
const session = require('express-session');
const app = express();

app.use(express.json());
app.use(express.static('public'));
app.use(session({
    secret: 'impactlink_secret',
    resave: false,
    saveUninitialized: false
}));

app.listen(3000, () => {
    console.log('Server running on http://localhost:3000');
});