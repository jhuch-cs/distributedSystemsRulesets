ruleset temperature_store {
    meta {
        name "Temperature Store"
        description <<
            A temperature module for learning about basic persistent state 
            >>
        author "Jared Huch"
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
        use module sensor_profile alias profile
    }
    global {
        temperatures = function() {
            ent:temps
        }

        threshold_violations = function() {
            ent:violations
        }

        inrange_temperatures = function() {
            ent:temps.difference(ent:violations);
        }
    }

    rule collect_temperatures {
        select when wovyn new_temperature_reading

        pre {
            temp_reading = event:attrs{"temperature"}
            temp_timestamp = event:attrs{"timestamp"}
        }

        always{
            ent:temps := ent:temps.defaultsTo([], "initialization was needed");
            ent:temps := ent:temps.append({"temperature": temp_reading, "time": temp_timestamp});
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation

        pre {
            temp_reading = event:attrs{"temperature"}
            temp_timestamp = event:attrs{"timestamp"}
        }

        always{
            ent:violations := ent:violations.defaultsTo([], "initialization was needed");
            ent:violations := ent:violations.append({"temperature": temp_reading, "time": temp_timestamp});
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset

        always {
            ent:temps := [];
            ent:violations := [];
        }
    }

    rule threshold_changed {
        select when wovyn sensor_profile_updated

        pre {
            didChange = event:attrs{"did_threshold_change"};
        }

        if didChange then noop()

        fired {
            ent:violations := ent:temps.filter(function(reading) { reading{"temperature"} > profile:getThreshold()});
        }
    }
}