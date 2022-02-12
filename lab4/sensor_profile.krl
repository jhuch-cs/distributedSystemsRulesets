ruleset sensor_profile {
    meta {
        name "Sensor Profile"
        description <<
            A representation of the profile for a sensor, including location, name, threshold and SMS number
            >>
        author "Jared Huch"
        provides getProfile, getThreshold, getPhoneNumber
        shares getProfile
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
    }

    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid

        if ent:location.isnull() || ent:name.isnull() || ent:threshold.isnull() || ent:phone_number.isnull() then noop()

        fired {
          ent:location := "Huch Home"
          ent:name := "Huch Sensor"
          ent:threshold := 75
          ent:phone_number := "+18474602997"
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