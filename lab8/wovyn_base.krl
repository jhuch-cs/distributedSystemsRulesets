ruleset wovyn_base {
    meta {
        name "Wovyn Base"
        description <<
            A base ruleset for interacting with the Wovyn sensor
            >>
        author "Jared Huch"
        use module sensor_profile alias profile
        use module io.picolabs.subscription alias subscription
    }
   
    global {
        use_imperial_units = true

        notifyOfViolation = defaction(sub, attrs) {
            event:send({ 
                "eci": sub{"Tx"},
                "eid": "notify-of-violation",
                "domain": "sensor",
                "type": "threshold_violation",
                "attrs": attrs
            })
        }

    }

    rule process_heartbeat {
        select when wovyn heartbeat

        pre {
            tempF = event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureF"}
            tempC = event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureC"}
        }

        if (event:attrs{"genericThing"}) then send_directive({"tempF": tempF, "tempC": tempC, "timestamp": event:time})

        fired {
            raise wovyn event "new_temperature_reading"
                attributes {"temperature": (use_imperial_units) => tempF | tempC, "use_imperial_units": use_imperial_units, "timestamp": event:time}
        }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading

        pre {
            temp = event:attrs{"temperature"}
            time = event:attrs{"timestamp"}
        }

        if (temp > profile:getThreshold()) then noop()
        fired {
            raise wovyn event "threshold_violation"
                attributes {"temperature": temp, "temperature_threshold": profile:getThreshold(), "timestamp": time}
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
            foreach subscription:established().filter(function(sub) { 
                sub{"Rx_role"} == "managing_sensor"
            }) setting (sub)

        notifyOfViolation(sub, event:attrs)
    }
}