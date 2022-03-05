ruleset sensor_profile {
    meta {
        name "Sensor Profile"
        description <<
            A representation of the profile for a sensor, including location, name, threshold and SMS number
            >>
        author "Jared Huch"
        provides getProfile, getThreshold, getPhoneNumber
        shares getProfile
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subscription
    }
    global {
        getProfile = function() {
            {
                "location": ent:location,
                "name": ent:name,
                "threshold": ent:threshold,
                "phone_number": ent:phone_number
            }
        }

        getThreshold = function() {
            ent:threshold
        }

        getPhoneNumber = function() {
            ent:phone_number
        }

        notifyParentOfInstallation = defaction() {
            event:send({
                "eci": wrangler:parent_eci(),
                "domain": "sensor", 
                "type": "profile_installed",
                "attrs": {"eci": meta:eci}
            })
        }

        notifyParentOfTx = defaction(Rx) {
            event:send({
                "eci": wrangler:parent_eci(),
                "domain": "sensor", 
                "type": "subscription_approved",
                "attrs": {
                    "wellKnown_Rx":subscription:wellKnown_Rx(){"id"},
                    "Tx": Rx // this picos Rx is parent's Tx
                }
            })
        }
    }

    rule sensor_intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid

        notifyParentOfInstallation();

        always {
          ent:location := "Huch Home"
          ent:name := "Huch Sensor"
          ent:threshold := 75
          ent:phone_number := "+18474602997"
        }
    }

    rule accept_subscription  {
        select when wrangler inbound_pending_subscription_added

        pre {
            rx_role = event:attrs{"Rx_role"}
            tx_role = event:attrs{"Tx_role"}
            rx = event:attrs{"Rx"}
        }

        if rx_role == "managing_sensor" && tx_role == "temperature_sensor" then notifyParentOfTx(rx)

        fired {
            raise wrangler event "pending_subscription_approval" 
                attributes event:attrs;
        }
    }

    rule update_profile {
        select when sensor profile_updated

        pre {
            new_location = event:attrs{"location"}
            new_name = event:attrs{"name"}
            new_threshold = event:attrs{"threshold"}
            new_phone_number = event:attrs{"phone_number"}
        }

        always {
            raise wovyn event "sensor_profile_updated" 
                attributes {"did_threshold_change": (new_threshold || new_threshold == 0) && new_threshold != ent:threshold}

            ent:location := new_location || ent:location
            ent:name := new_name || ent:name
            ent:threshold := new_threshold || ent:threshold
            ent:phone_number := new_phone_number || ent:phone_number
        }
    }
}