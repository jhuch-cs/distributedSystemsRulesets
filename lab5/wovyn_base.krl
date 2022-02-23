ruleset wovyn_base {
    meta {
        name "Wovyn Base"
        description <<
            A base ruleset for interacting with the Wovyn sensor
            >>
        author "Jared Huch"
        // Commented out because I don't want my phone to be spammed while testing dependent rulesets:
        // use module com.twilio.sdk alias sdk
        //     with
        //         auth_token = meta:rulesetConfig{"auth_token"}
        //         sid = meta:rulesetConfig{"sid"}
        use module sensor_profile alias profile
    }
   
    global {
        use_imperial_units = true
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

        pre {
            temp = event:attrs{"temperature"}
            threshold = event:attrs{"temperature_threshold"}
            uses_imperial = event:attrs{"use_imperial_units"}
        }

        // Commented out because I don't want my phone to be spammed while testing dependent rulesets:
        // sdk:sendMessage(<<Temperature of #{temp}#{(uses_imperial) => "F" | "C"} exceeds threshold of #{threshold}>>, profile:getPhoneNumber()) setting(response)
    }


}