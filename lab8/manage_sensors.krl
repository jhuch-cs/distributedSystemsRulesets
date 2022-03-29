ruleset manage_sensors {
    meta {
        name "Sensor Profile"
        description <<
            A ruleset to manage the picos controlling various temperature sensors
            >>
        author "Jared Huch"
        shares sensors, tempSensors, getAllTemps, getTempReports
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subscription
    }
    global {
        sensors = function() { // only used for testing
            ent:sensors
        }

        tempSensors = function() {
            subscription:established().filter(function(subscription) { subscription{"Rx_role"} == "temperature_sensor" });
        } 

        getAllTemps = function() {
            tempSensors().map(function(subscription_info) { 
                subscription_host = subscription_info{"Tx_host"} || meta:host;

                {}.put(subscription_info{"Tx"}, wrangler:picoQuery(subscription_info{"Tx"}, "temperature_store", "temperatures", _host=subscription_host))
            })
        }

        getTempReports = function() {
            rcns = ent:reports_rcns.length() >= 5 => // get the 5 (or fewer) most recent reports
                        ent:reports_rcns.slice(4) | 
                        ent:reports_rcns.slice(ent:reports_rcns.length())
            ent:reports.filter(function(value,key) { rcns >< key })
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
                    "name": name,
                    "threshold": threshold, 
                  }
                }
            )
        }

        sensor_rulesets = [
            "file:///C:/Users/jared/Documents/College/cs462/lab8/io.picolabs.wovyn.emitter.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab8/sensor_profile.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab8/wovyn_base.krl",
            "file:///C:/Users/jared/Documents/College/cs462/lab8/temperature_store.krl"
        ]
        defaultThreshold = 73
        royal_blue = "#3757bf"

    }

    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid

        noop()

        always {
          ent:sensors := {}
        }
    }

    rule create_new_sensor { 
        select when sensor new_sensor

        pre {
            name = event:attrs{"name"}
        }

        if not (ent:sensors.keys() >< name) then noop() // can still use ent:sensors for name tracking

        fired {
            raise wrangler event "new_child_request"
                    attributes { "name": name, "backgroundColor": royal_blue }
        }
    }

    rule new_sensor_created {
        select when wrangler new_child_created

        pre {
            eci = event:attrs{"eci"}
            name = event:attrs{"name"}
        }

        always {
            ent:sensors{name} := {"eci":eci}
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
            name = ent:sensors.filter(function(value, key) { value{"eci"} == eci }).keys()[0] // can still use ent:sensors for name tracking
            wellKnown_Rx = wrangler:picoQuery(eci,"io.picolabs.subscription","wellKnown_Rx"){"id"}
        }

        if name then updateProfile(eci, name, defaultThreshold)

        fired {
            ent:sensors{name} := ent:sensors{name}.put({"wellKnown_Rx": wellKnown_Rx})
            raise wrangler event "subscription" 
                attributes {
                    "Rx_role": "temperature_sensor",
                    "Tx_role": "managing_sensor",
                    "wellKnown_Tx": wellKnown_Rx
                }
        }
    }

    rule store_tx {
        select when sensor subscription_approved

        pre {
            wellKnown_Rx = event:attrs{"wellKnown_Rx"}
            name = ent:sensors.filter(function(value, key) { value{"wellKnown_Rx"} == wellKnown_Rx }).keys()[0] // can still use ent:sensors for name tracking
            Tx = event:attrs{"Tx"}
        }

        if name && Tx then noop()

        fired {
            ent:sensors{name} := ent:sensors{name}.put({"Tx": Tx})
        }
    }

    rule subscribe_to_pico {
        select when sensor subscription_request 

        pre {
            wellKnown_Rx = event:attrs{"wellKnown_Rx"}
            Rx_host = event:attrs{"Rx_host"}
        }

        if Rx_host then noop()

        fired {
            raise wrangler event "subscription" 
                attributes {
                    "Rx_role": "temperature_sensor",
                    "Tx_role": "managing_sensor",
                    "wellKnown_Tx": wellKnown_Rx,
                    "Tx_host": Rx_host 
                }
        } else {
            raise wrangler event "subscription" 
                attributes {
                    "Rx_role": "temperature_sensor",
                    "Tx_role": "managing_sensor",
                    "wellKnown_Tx": wellKnown_Rx
                }
        }
    }

    rule request_temperature_report {
        select when sensor begin_temperature_report
            foreach tempSensors() setting(sensor)

        pre {
            rcn = event:attrs{"rcn"}
            tx = sensor{"Tx"}
            rx = sensor{"Rx"}
            host = sensor{"Tx_host"} || meta:host
        }

        event:send(
            { "eci": tx,
              "eid": "create-report",
              "domain": "sensor",
              "type": "create_temperature_report",
              "attrs": {
                "rcn": rcn,
                "host": meta:host, // for callback
                "rx": rx
              }
            },
            host=host
        )

        always {
            ent:reports_rcns := ent:reports_rcns.defaultsTo([], "initialization was needed") on final
            ent:reports_rcns := ent:reports_rcns.reverse().append(rcn).reverse() on final // prepend, so most recent rcns at front
            ent:reports := ent:reports.defaultsTo({}, "initialization was needed") on final
            ent:reports{rcn} := {"temperature_sensors": tempSensors().length(), "responding": 0, "temperatures": []} on final
        }
    }

    rule sub_report_received {
        select when sensor report_created

        pre {
            rcn = event:attrs{"rcn"}
            temp = event:attrs{"reading"}
        }

        always {
            ent:reports{[rcn, "temperatures"]} := ent:reports{[rcn, "temperatures"]}.append(temp)
            ent:reports{[rcn, "responding"]} := ent:reports{[rcn, "responding"]} + 1
            raise sensor event "finished_temperature_report" if ent:reports{[rcn, "responding"]} == ent:reports{[rcn, "temperature_sensors"]}
        }
    }

    rule delete_sensor {
        select when sensor unneeded_sensor

        pre {
            name_to_delete = event:attrs{"name"}
            sensor_info = ent:sensors{name_to_delete} // can still use ent:sensors for name tracking
            eci_to_delete = sensor_info{"eci"} 
            Tx_to_delete = sensor_info{"Tx"}
        }

        always {
            raise wrangler event "child_deletion_request"
                attributes {"eci": eci_to_delete};
            raise wrangler event "subscription_cancellation" 
                attributes {"Tx":Tx_to_delete}
        }
    }

    rule sensor_deleted {
        select when wrangler child_deleted

        pre {
            eci_of_deleted = event:attrs{"eci"}
            name = ent:sensors.filter(function(value, key) { value{"eci"} == eci_of_deleted }).keys()[0] // can still use ent:sensors for name tracking
        }

        always {
            clear ent:sensors{name}
        }
    }

    rule delete_all {
        select when sensor clear_sensors foreach ent:sensors setting (val, name)

        if name then noop()

        fired {
            raise sensor event "unneeded_sensor"
                attributes {"name": name}
        }
    }
}