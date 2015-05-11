class ProfileContactsController
    @.$inject = [
        "tgUserService",
        "$tgAuth"
    ]

    constructor: (@userService, @auth) ->

    loadContacts: () ->
        userId = @auth.getUser().id

        @userService.getContacts(userId)
            .then (contacts) =>
                @.contacts = contacts

angular.module("taigaProfile")
    .controller("ProfileContacts", ProfileContactsController)
