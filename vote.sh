#!/bin/bash
function __VoteStatus() {

  PROPOSALS=$(${COSMOS} query gov proposals --status VotingPeriod --home ${NODE_HOME} --output json 2>/dev/null | jq -r '.proposals[]|to_entries[]|select(.key|contains("id"))|.value')
  if [[ -z "$PROPOSALS" ]]; then
    echo "No voting period proposals"
  else
    echo "List of voting period proposals: ${PROPOSALS}"
  fi
  SEND_STORE=$(dirname -- $(readlink -f -- $0))/.${PROJECT}_send
  for PROP_ID in $PROPOSALS; do
    VOTED=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null | jq -r '.options[].option')
    if [[ -z "$VOTED" ]]; then
      echo "Start voting routine on proposal ${PROP_ID}"
      if [[ -e "${SEND_STORE}" && $(cat "${SEND_STORE}" | grep -m1 ${PROP_ID}) = "${PROP_ID}_sent" ]]; then
        echo "Proposal ${PROP_ID} already sent to telegram"
      else
        echo "Send proposal ${PROP_ID} to telegram"
        prop_info=$(${COSMOS} query gov proposal $PROP_ID --home ${NODE_HOME} --output json)
        prop_info_title=$(jq -r '..|objects|.title//empty' <<<$prop_info)
        prop_info_descr=$(jq -r '..|objects|.description//empty' <<<$prop_info | sed -e 's/<[^>]*>//g' -e 's/&/\&amp;/g' -e 's/>/\&gt;/g' -e 's/</\&lt;/g')
        prop_info_start=$(jq -r '.voting_start_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime|strftime("%Y-%m-%d %H:%M %Z")' <<<$prop_info)
        prop_info_end=$(jq -r '.voting_end_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime|strftime("%Y-%m-%d %H:%M %Z")' <<<$prop_info)
        prop_info="<b>${PROJECT} proposal ID: ${PROP_ID}</b>\n<b>${prop_info_title}</b>\n<i>${prop_info_descr}</i>\n<b>Voting start:</b> ${prop_info_start}\n<b>Voting end:</b> ${prop_info_end}"
        curl -s -X POST -H 'Content-Type: application/json' \
          -d '{"chat_id":"'"${CHAT_ID_ALARM}"'", "text": "'"${prop_info}"'", "parse_mode": "html", "reply_markup": {"inline_keyboard": [[{"text": "Yes ✅", "callback_data": "'"${PROJECT}"'|'"${PROP_ID}"'|yes"},{"text": "No ❌", "callback_data": "'"${PROJECT}"'|'"${PROP_ID}"'|no"},{"text": "Veto ⛔️", "callback_data": "'"${PROJECT}"'|'"${PROP_ID}"'|no_with_veto"},{"text": "Abstain 🤔", "callback_data": "'"${PROJECT}"'|'"${PROP_ID}"'|abstain"}]]}}' https://api.telegram.org/bot${BOT_TOKEN}/sendMessage >/dev/null 2>&1
        echo "${PROP_ID}_sent" >>${SEND_STORE}
      fi
      #get callback from telegram
      CALLBACK=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" | jq -r '.result|map(select(.callback_query.data))|.[].callback_query.data|=split("|")|map({message_id: .callback_query.message.message_id, project: .callback_query.data[0], prop_id: .callback_query.data[1], vote: .callback_query.data[2]})|reverse|unique_by(.prop_id)|.[]' 2>/dev/null)
      if [[ -z $(jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.prop_id' <<<${CALLBACK}) ]]; then
        if $(${COSMOS} query gov proposal $PROP_ID --home ${NODE_HOME} --output json | jq --argjson v $VOTE_BEFORE '.voting_end_time|strptime("%Y-%m-%dT%H:%M:%S.%Z")|mktime > (now+$v)'); then
          echo "Waiting for auto-vote time"
        else
          VOTE=$(${COSMOS} query gov tally $PROP_ID --home ${NODE_HOME} --output json | jq -r 'to_entries|.[].value|=tonumber|max_by(.value)|.key|sub("_count";"")')
          yes ${PASWD} | ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} --fees ${FEES} --gas ${GAS} -y 2>/dev/null
          sleep 30
          VOTE_CHK=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null | jq -r '.options[].option|sub("VOTE_OPTION_";"")')
          if [[ -n "$VOTE_CHK" ]]; then
            curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID_ALARM}"'", "text": "Voted <b>'"${VOTE_CHK}"'</b> for proposal <b>'"${PROP_ID}"'</b> in <b>'"${PROJECT}"'</b> automaticaly, because voting period end soon", "parse_mode": "html"}' https://api.telegram.org/bot${BOT_TOKEN}/sendMessage >/dev/null 2>&1
            echo "Voted \"${VOTE_CHK}\" for proposal ${PROP_ID}, because voting period end soon"
          fi
        fi
      else
        if [[ "${PROP_ID}" -eq $(jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.prop_id' <<<${CALLBACK}) ]]; then
          VOTE=$(jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.vote' <<<${CALLBACK})
          yes ${PASWD} | ${COSMOS} tx gov vote $PROP_ID $VOTE --home ${NODE_HOME} --keyring-backend ${KEYRING} --from ${DELEGATOR_ADDRESS} --fees ${FEES} --gas ${GAS} -y 2>/dev/null
          sleep 30
          VOTE_CHK=$(${COSMOS} query gov vote $PROP_ID ${DELEGATOR_ADDRESS} --home ${NODE_HOME} --output json 2>/dev/null | jq -r '.options[].option|sub("VOTE_OPTION_";"")')
          if [[ -n "$VOTE_CHK" ]]; then
            MSG_ID=$(jq -r --arg id ${PROP_ID} 'select(.prop_id==$id)|.message_id' <<<${CALLBACK})
            curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id":"'"${CHAT_ID_ALARM}"'", "text": "Voted <b>'"${VOTE_CHK}"'</b> for proposal <b>'"${PROP_ID}"'</b> as you selected", "parse_mode": "html", "reply_to_message_id": "'"${MSG_ID}"'"}' https://api.telegram.org/bot${BOT_TOKEN}/sendMessage >/dev/null 2>&1
            echo "Voted \"${VOTE}\" for proposal ${PROP_ID}, as selected in telegram"
          fi
        fi
      fi
    else
      echo "Already voted \"${VOTED}\" for proposal ${PROP_ID}"
    fi
  done
}

function Main() {
  cd $HOME/status
  for CONF in *.conf; do
    if [[ "${CONF}" != *"COSMOS"* ]]; then
      # read config
      source ./${CONF}
      NODE_HOME=$(dirname "$CONFIG")
      echo "-------- $(date +"%d-%m-%Y %H:%M") start vote check for ${PROJECT} --------"
      # run 'VoteStatus'
      __VoteStatus
      echo -e "-------- $(date +"%d-%m-%Y %H:%M") vote check done for ${PROJECT} ---------\n"
    fi
  done
}

# run 'main'
Main
