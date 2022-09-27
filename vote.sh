#!/bin/bash

# -- CONFIG ZONE START --
PROJECT="COSMOS"
VOTE_BEFORE=600 # vote time window in seconds before end of voting, used for auto vote
COSMOS="/usr/local/bin/gaiad" # set your chain binary
NODE_HOME="/root/.cosmos" # path to config folder
KEYRING="test"
PASWD=""
DELEGATOR_ADDRESS="cosmos1..." # wallet address for sending vote tx, must be in keys list (only test keyring for now)
CHAT_ID_STATUS="11223344" # telegram chat id
BOT_KEY="1122334455:Aabb..." # telegram bot token
# -- CONFIG ZONE END --

echo "-------- $(date +"%d-%m-%Y %H:%M") start vote check --------"
PROPOSALS=$(${COSMOS} query gov proposals --status VotingPeriod --home ${NODE_HOME} --output json 2>/dev/null|jq -r '.proposals[]|to_entries[]|select(.key|contains("id"))|.value')
if [[ -z "$PROPOSALS" ]]; then
  echo "No voting period proposals, exit"
  echo "-------- $(date +"%d-%m-%Y %H:%M") vote check done ---------"
  exit 1
else
  echo "List of VotingPeriod proposals: ${PROPOSALS}"
fi
for PROP_ID in $PROPOSALS; do
    VOTED=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null|jq -r '.options[].option')
    if [[ -z "$VOTED" ]]
    then
        echo "Start voting routine on proposal ${PROP_ID}"
        if [[ -e "./${PROJECT}_VOTING" && $(cat "./${PROJECT}_VOTING"|grep -m1 ${PROP_ID}) = "${PROP_ID}_sended" ]]
        then
            echo "Proposal ${PROP_ID} already sended to telegram"
        else
            echo "Send proposal ${PROP_ID} to telegram"
            prop_info=$(${COSMOS} query gov proposal $PROP_ID --home ${NODE_HOME} --output json)
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
        CALLBACK=$(curl -s "https://api.telegram.org/bot${BOT_KEY}/getUpdates"|jq -r '.result[].callback_query.data|=split("_")|.result|map({message_id: .callback_query.message.message_id, project: .callback_query.data[0], prop_id: .callback_query.data[1], vote: .callback_query.data[2]})|reverse|unique_by(.prop_id)|.[]' 2>/dev/null)
        if [[ -z $(echo ${CALLBACK}|jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.prop_id') ]]
        then
            if $(${COSMOS} query gov proposal $PROP_ID --home ${NODE_HOME} --output json|jq --argjson v $VOTE_BEFORE '.voting_end_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime > (now+$v)')
            then
                echo "Whait for autovoting time become"
            else
                VOTE=$(${COSMOS} query gov tally $PROP_ID --home ${NODE_HOME} --output json|jq -r 'to_entries|.[].value|=tonumber|max_by(.value)|.key|sub("_count";"")')
                if [[ ${KEYRING} = "test" ]]
                then
                    ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                else
                    echo -e "${PASWD}\n${PASWD}\n" | ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                fi
                sleep 5
                VOTE_CHK=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null|jq -r '.options[].option|sub("VOTE_OPTION_";"")')
                if [[ -n "$VOTE_CHK" ]]
                then
                    curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID_STATUS}"'", "text": "Voted <b>'"${VOTE_CHK}"'</b> for proposal <b>'"${PROP_ID}"'</b> in <b>'"${PROJECT}"'</b> automaticaly, because voting period end soon", "parse_mode": "html"}' https://api.telegram.org/bot${BOT_KEY}/sendMessage > /dev/null 2>&1
                    echo "Voted \"${VOTE_CHK}\" for proposal ${PROP_ID}, because voting period end soon"
                fi
            fi
        else
            if [[ "${PROP_ID}" -eq $(echo ${CALLBACK}|jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.prop_id') ]]
            then
                VOTE=$(echo ${CALLBACK}|jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.vote')
                if [[ ${KEYRING} = "test" ]]
                then
                    ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                else
                    echo -e "${PASWD}\n${PASWD}\n" | ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} -y 2>/dev/null
                fi
                sleep 5
                VOTE_CHK=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null|jq -r '.options[].option|sub("VOTE_OPTION_";"")')
                if [[ -n "$VOTE_CHK" ]]
                then
                    MSG_ID=$(echo ${CALLBACK}|jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.message_id')
                    curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID_STATUS}"'", "text": "Voted <b>'"${VOTE_CHK}"'</b> for proposal <b>'"${PROP_ID}"'</b> as you selected", "parse_mode": "html", "reply_to_message_id": "'"${MSG_ID}"'"}' https://api.telegram.org/bot${BOT_KEY}/sendMessage > /dev/null 2>&1
                    echo "Voted \"${VOTE}\" for proposal ${PROP_ID}, as selected in telegram"
                fi
            fi
        fi
    else
        echo "Already voted \"${VOTED}\" for proposal ${PROP_ID}"
    fi
done
echo "-------- $(date +"%d-%m-%Y %H:%M") vote check done --------"
