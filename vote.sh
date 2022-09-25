#!/bin/bash

# -- CONFIG ZONE START --
PROJECT="COSMOS"
VOTE_BEFORE=600 # vote time window in seconds before end of voting, used for auto vote
COSMOS="/usr/local/bin/gaiad" # set your chain binary
DELEGATOR_ADDRESS="cosmos1..." # wallet address for sending vote tx, must be in keys list (only test keyring for now)
CHAT_ID_STATUS="11223344" # telegram chat id
BOT_KEY="1122334455:Aabb..." # telegram bot token
# -- CONFIG ZONE END --

echo "$(date +"%Y-%m-%d_%H-%M-%S") Start proposal vote check"
PROPOSALS=$(${COSMOS} query gov proposals --status VotingPeriod --output json 2>/dev/null|jq -r '.proposals[]|to_entries[]|select(.key|contains("id"))|.value')
if [[ -z "$PROPOSALS" ]]; then
  echo "No voting period proposals, exit"
  echo "$(date +"%Y-%m-%d_%H-%M-%S") Check done"
  exit 1
else
  echo "List of VotingPeriod proposals: ${PROPOSALS}"
fi
for PROP_ID in $PROPOSALS; do
    VOTED=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --output json 2>/dev/null|jq -r '.options[].option')
    if [[ -z "$VOTED" ]]
    then
        echo "Start voting routine on proposal ${PROP_ID}"
        if [[ -e "./${PROJECT}_VOTING" && $(cat "./${PROJECT}_VOTING"|grep -m1 ${PROP_ID}) = "${PROP_ID}_sended" ]]
        then
            echo "Proposal ${PROP_ID} already sended to telegram"
        else
            echo "Send proposal ${PROP_ID} to telegram"
            prop_info=$(${COSMOS} query gov proposal $PROP_ID --output json)
            prop_info_title=$(echo $prop_info | jq -r '..|objects|.title//empty')
            prop_info_descr=$(echo $prop_info | jq -r '..|objects|.description//empty'|sed -e 's/<[^>]*>//g')
            prop_info_start=$(echo $prop_info | jq -r '.voting_start_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime|strftime("%Y-%m-%d %H:%M %Z")')
            prop_info_end=$(echo $prop_info | jq -r '.voting_end_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime|strftime("%Y-%m-%d %H:%M %Z")')
            prop_info="<b>${PROJECT} proposal ID: ${PROP_ID}</b>\n<b>${prop_info_title}</b>\n<i>${prop_info_descr}</i>\n<b>Voting start:</b> ${prop_info_start}\n<b>Voting end:</b> ${prop_info_end}"
            curl -s -X POST -H 'Content-Type: application/json' \
            -d '{"chat_id":"'"${CHAT_ID_STATUS}"'", "text": "'"${prop_info}"'", "parse_mode": "html", "reply_markup": {"inline_keyboard": [[{"text": "Yes ✅", "callback_data": "'"${PROJECT}"'_'"${PROP_ID}"'_yes"},{"text": "No ❌", "callback_data": "'"${PROJECT}"'_'"${PROP_ID}"'_no"},{"text": "No(Veto) ⛔️", "callback_data": "'"${PROJECT}"'_'"${PROP_ID}"'_veto"},{"text": "Abstain 🤔", "callback_data": "'"${PROJECT}"'_'"${PROP_ID}"'_abstain"}]]}}' https://api.telegram.org/bot$BOT_KEY/sendMessage > /dev/null 2>&1
            echo "${PROP_ID}_sended" >> ./${PROJECT}_VOTING
        fi
        #get callback from telegram
        CALLBACK=$(curl -s "https://api.telegram.org/bot${BOT_KEY}/getUpdates"|jq -r '.result|max_by(.update_id)|.callback_query.data|split("_")' 2>/dev/null)
        if [[ -z "${CALLBACK}" ]]
        then
            if $(${COSMOS} query gov proposal $PROP_ID --output json|jq --argjson v $VOTE_BEFORE '.voting_end_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime > (now+$v)')
            then
                echo "Whait for autovoting time become"
            else
                VOTE=$(${COSMOS} query gov tally $PROP_ID --output json|jq -r 'to_entries|.[].value|=tonumber|max_by(.value)|.key'|sed s/_count//)
                ${COSMOS} tx gov vote $PROP_ID $VOTE --keyring-backend test --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                echo "Voted \"${VOTE}\" for proposal ${PROP_ID}, because voting period end soon"
            fi
        else
            if [[ $PROP_ID -eq $(echo $CALLBACK|jq -r .[1]) ]]
            then
                VOTE=$(echo $CALLBACK|jq -r .[2])
                ${COSMOS} tx gov vote $PROP_ID $VOTE --keyring-backend test --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                echo "Voted \"${VOTE}\" for proposal ${PROP_ID}, as selected in telegram"
            fi
        fi
    else
        echo "Already voted \"${VOTED}\" for proposal ${PROP_ID}"
    fi
done
echo "$(date +"%Y-%m-%d_%H-%M-%S") Check done"
