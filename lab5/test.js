async function httpGet(url) {
    response = await fetch(url);
    return response.json();
}

let managerEci = "ckzzswjkm000b1kvof70rhzdj";

let clearSensorsURL = `http://localhost:3000/c/${managerEci}/event-wait/sensor/clear_sensors`;
let createSensorURL = `http://localhost:3000/c/${managerEci}/event-wait/sensor/new_sensor/?name=`;
let listSensorsURL  = `http://localhost:3000/c/${managerEci}/query/manage_sensors/sensors`;
let deleteSensorURL = `http://localhost:3000/c/${managerEci}/event-wait/sensor/unneeded_sensor?name=`;


/*
    1. CREATE 3 PICOS AND DELETE 1
*/
let nameBase = "MyPico";

async function createPicos(numPicos) {
    for (let i = 1; i <= numPicos; i++) {
        await httpGet(createSensorURL + escape(nameBase + i));
    }
}

async function assertSensorLength_getName(sensorLength) {
    let sensors = await httpGet(listSensorsURL);
    console.assert(Object.keys(sensors).length === sensorLength);
    return sensors[Object.keys(sensors)[0]]
}

async function assertSensorLength_getEci(sensorLength) {
    let sensors = await httpGet(listSensorsURL);
    console.assert(Object.keys(sensors).length === sensorLength);
    return Object.keys(sensors)[0]
}

await httpGet(clearSensorsURL); // ensure we have 0 children to begin

await createPicos(3)

let sensorToDelete = await assertSensorLength_getName(3);

await httpGet(deleteSensorURL + escape(sensorToDelete));

let sensorToTest = await assertSensorLength_getEci(2);


/*
    2. TEST SENSORS WITH TEMP EVENTS
*/

let newTempURL   = `http://localhost:3000/c/${managerEci}/event-wait/sensor/request_event_forwarding?eci=${sensorToTest}&domain=emitter&type=new_sensor_reading`;
let listTempsURL = `http://localhost:3000/c/${managerEci}/query/child_forwarding/requestQueryForwarding?child_eci=${sensorToTest}&ruleset_rid=temperature_store&func_name=temperatures`;

let numTemps = await httpGet(listTempsURL)
numTemps = Object.keys(numTemps ?? {}).length

await (async () => { // one day javascript won't be dumb, but until that day, I'll use immediately invoked functions for `async` loops
    for (let i = 0; i < 3; i++) {
        await httpGet(newTempURL);
    }
})()

let temps = await httpGet(listTempsURL);
console.assert(Object.keys(temps).length >= numTemps + 3); // >= because the emitter could have released an unrequested reading (from heartbeat) in the interval it takes to complete these requests


/*
    3. TEST THAT THE SENSOR PROFILE IS SET RELIABLY (NO RACE CONDITIONS AROUND `name` IN PARTICULAR)
*/

async function getProfileName(eci) {
    let profileURL = `http://localhost:3000/c/${managerEci}/query/child_forwarding/requestQueryForwarding?child_eci=${eci}&ruleset_rid=sensor_profile&func_name=getProfile`;
    let profile = await httpGet(profileURL);
    let name = profile["name"];
    return name;
}

await createPicos(10); // increase sample size to increase confidence that race-conditions are controlled

let sensors = await httpGet(listSensorsURL);

await (async () => {
    for (eci in sensors) {
        let expectedName = sensors[eci];
        let profileName = await getProfileName(eci);
        console.assert(expectedName === profileName); // the name used when creating the pico is used in the profile
    }
})()

/*
    CLEAN UP 
*/

await httpGet(clearSensorsURL); // ensure we have 0 children to end
