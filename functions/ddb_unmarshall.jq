def unmarshall:
  walk(
    if type == "object" and length == 1 then
      if   has("NULL") then null
      elif has("BOOL") then .BOOL
      elif has("S")    then .S
      elif has("B")    then .B
      elif has("N")    then .N | tonumber
      elif has("M")    then .M | unmarshall
      elif has("L")    then .L | map(unmarshall)
      elif has("SS")   then .SS | map(unmarshall)
      elif has("NS")   then .NS | map(tonumber)
      elif has("BS")   then .BS
      else .
      end
    elif type == "array" then map(unmarshall)
    else .
    end
  );

unmarshall
