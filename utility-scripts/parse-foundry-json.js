const fs = require('fs');

// Read input JSON data from file (assuming it's saved as input.json)
const inputJson = fs.readFileSync('safe-registration-file.json', 'utf8');

// Parse the JSON data
const data = JSON.parse(inputJson);

// Remove the surrounding quotes from the string
const trimmedString = data.transactions.substring(1, data.transactions.length - 1);

// // Replace escaped backslashes with a single backslash
let cleanedString = trimmedString.replace(/\\\\/g, '\\');
cleanedString = cleanedString.replace(/\"{/g, '{');
cleanedString = "[" + cleanedString.replace(/\}"/g, '}') + "]";

// Parse the cleaned string into a JavaScript array
const jsonArray = JSON.parse(cleanedString);

// Update the data object with the parsed transactions array
data.transactions = jsonArray;

// Convert data back to JSON format
const outputJson = JSON.stringify(data, null, 2);

// Print the output JSON
fs.writeFileSync('safe-registration-file.json', outputJson, 'utf8')
