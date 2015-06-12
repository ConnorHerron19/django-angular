class ProfileHints
    HINTS: [
        { #hint1
            url: "https://taiga.io/support/import-export-projects/"
        },
        { #hint2
            url: "https://taiga.io/support/custom-fields/"
        },
        { #hint3
        },
        { #hint4
        }
    ]
    constructor: (@translate) ->
        hintKey = Math.floor(Math.random() * @.HINTS.length) + 1

        @.hint = @.HINTS[hintKey - 1]

        @.hint.linkText = @.hint.linkText || 'HINTS.LINK'

        @translate("HINTS.HINT#{hintKey}_TITLE").then (text) =>
            @.hint.title = text

        @translate("HINTS.HINT#{hintKey}_TEXT").then (text) =>
            @.hint.text = text

ProfileHints.$inject = [
    "$translate"
]

angular.module("taigaProfile").controller("ProfileHints", ProfileHints)
