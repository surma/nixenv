#!/usr/bin/env nu

let dotenv = (open /data/env | from toml)
let token = ({role: "admin"} | jwt encode -s user1 -S $dotenv.JWT_SECRET --exp=1y ($in | to json))
http post --content-type application/json --headers ["Authorization" $"Bearer ($in)"] -fe https://writing-prompt.surma.technology/api/prompt/activate-next {template: "Here is your new writing prompt! {{prompt}}" }
