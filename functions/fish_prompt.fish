function fish_prompt --description "wrap starship prompt to fix environment variables not refreshed"
  if not functions --query starship_fish_prompt
    # rename fish_prompt by starship
    source (starship init fish --print-full-init | string replace fish_prompt starship_fish_prompt | psub)
  end

  set --global --export AWS_PROFILE $AWS_PROFILE
  starship_fish_prompt
  set --erase AWS_PROFILE
end
