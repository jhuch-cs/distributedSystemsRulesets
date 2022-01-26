ruleset wovyn_base {
    meta {
        name "Wovyn Base"
        description <<
            A base ruleset for interacting with the Wovyn sensor
            >>
        author "Jared Huch"
        use module com.twilio.sdk alias sdk
            with
                auth_token = meta:rulesetConfig{"auth_token"}
                sid = meta:rulesetConfig{"sid"}
    }
   
    global {
        use_imperial_units = true
        temperature_threshold = 65
        number_to_notify = "+18474602997"
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
        }

        if (temp > temperature_threshold) then noop()
        fired {
            raise wovyn event "threshold_violation"
                attributes {"temperature": temp, "temperature_threshold": temperature_threshold, "timestamp": event:time}
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation

        pre {
            temp = event:attrs{"temperature"}
            threshold = event:attrs{"temperature_threshold"}
            uses_imperial = event:attrs{"use_imperial_units"}
        }

        sdk:sendMessage(<<Temperature of #{temp}#{(uses_imperial) => "F" | "C"} exceeds threshold of #{threshold}>>, number_to_notify) setting(response)
    }


}