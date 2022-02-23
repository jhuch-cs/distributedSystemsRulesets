ruleset manage_sensors {
    meta {
        name "Sensor Profile"
        description <<
            A ruleset to manage the picos controlling various temperature sensors
            >>
        author "Jared Huch"
        shares sensors, getAllTemps
        use module io.picolabs.wrangler alias wrangler
    }
    global {
        sensors = function() {
            ent:sensors
        }

        getAllTemps = function() {
            ent:sensors.keys().map(function(child_eci) { 
                {}.put(child_eci, wrangler:picoQuery(child_eci, "temperature_store", "temperatures")) 
            })
        }

        installRuleset = defaction(pico_at, which_ruleset) {
            event:send(
                { "eci": pico_at,
                  "eid": "install-ruleset",
                  "domain": "wrangler",
                  "type": "install_ruleset_request",
                  "attrs": {
                    "url": which_ruleset,
                  }
                }
            )
        }

        updateProfile = defaction(pico_eci, name, threshold) {
            event:send(
                { "eci": pico_eci,
                  "eid": "update-profile",
                  "domain": "sensor",
                  "type": "profile_updated",
                  "attrs": {
                    // "location": location // set automatically by profile
                    "name": name,
                    "threshold": threshold, 
                    // "phone_number": phone_number // set automatically by the profile
                  }
                }
            )
        }

        sensor_rulesets = [
            "file:///C:/Users/jared/Documents/College/cs462/lab5/io.picolabs.wovyn.emitter.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab5/sensor_profile.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab5/wovyn_base.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab5/temperature_store.krl"
        ]
        defaultThreshold = 73
        royal_blue = "#3757bf"

    }

    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid

        noop()

        always {
          ent:sensors := {}
          ent:picos_created := 0
        }
    }

    rule create_new_sensor { 
        select when sensor new_sensor

        pre {
            section_id = ent:picos_created
            name = event:attrs{"name"}
        }

        if not (ent:sensors.values() >< name) then noop()

        fired {
            raise wrangler event "new_child_request"
                    attributes { "name": name, "backgroundColor": royal_blue }
            ent:picos_created := ent:picos_created + 1
        }
    }

    rule new_sensor_created {
        select when wrangler new_child_created

        pre {
            eci = event:attrs{"eci"}
            name = event:attrs{"name"}
        }

        always {
            ent:sensors{eci} := name
            raise sensor event "install_ruleset_request"
                    attributes { "name": name, "eci": eci }
        }
    }

    rule install_sensor_rulesets {
        select when sensor install_ruleset_request 
            foreach sensor_rulesets setting (url) 

        pre {
            eci = event:attrs{"eci"}
        }

        installRuleset(eci, url)
    }

    rule sensor_profile_installed {
        select when sensor profile_installed

        pre {
            eci = event:attrs{"eci"}
            name = ent:sensors{eci}
        }

        if name then updateProfile(eci, name, defaultThreshold)
    }

    rule delete_sensor {
        select when sensor unneeded_sensor

        pre {
            name_to_delete = event:attrs{"name"}
            eci_to_delete = ent:sensors.filter(function(value, key) { value == name_to_delete }).keys()[0]
        }

        always {
            raise wrangler event "child_deletion_request"
                attributes {"eci": eci_to_delete};
        }
    }

    rule sensor_deleted {
        select when wrangler child_deleted

        pre {
            eci_of_deleted = event:attrs{"eci"}
        }

        always {
            clear ent:sensors{eci_of_deleted}
        }
    }

    rule delete_all {
        select when sensor clear_sensors foreach ent:sensors setting (name, eci)

        if name then noop()

        always {
            raise sensor event "unneeded_sensor"
                attributes {"name": name}
        }
    }
}