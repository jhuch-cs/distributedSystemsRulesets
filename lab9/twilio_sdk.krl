ruleset com.twilio.sdk {
    meta {
        name "Twilio SDK"
        description <<
            An SDK for interacting with the Twilio API
            >>
        author "Jared Huch"
        configure using
            auth_token = ""
            sid = ""
        shares getAuth, getSid
        provides messages, sendMessage
    }
    global {

        getAuth = function() {
            sid
        }

        getSid = function() {
            auth_token
        }

        base_url = "https://api.twilio.com/2010-04-01/"

        messages = function(page_size=0, to_number="", from_number="") {
            queryString = {}.put((page_size) => {"PageSize":page_size} | {}).put((to_number) => {"To":to_number} | {}).put((from_number) => {"From":from_number} | {})
            authentication = {"username":sid,"password":auth_token}
            response = http:get(<<#{base_url}/Accounts/#{sid}/Messages.json>>, qs = queryString, auth = authentication)
            response
        }

        sendMessage = defaction(msg, to_number) {
            authentication = {"username":sid,"password":auth_token}
            form = {"From":"+19362435766", "Body":msg, "To":to_number}
            url = <<#{base_url}Accounts/#{sid}/Messages.json>>.klog("Url to post to: ")
            http:post(url, auth=authentication, form=form) setting(response)
            return response.klog("Response from API: ")
        }
    }
}
