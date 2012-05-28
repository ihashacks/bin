{
if(NF == 6 && $4 == "A") {
   split($5,hostip,".");
   if(hostip[3] == "1")
   printf("%s\tIN\tPTR\t%s.domain.com.\n",hostip[4],$1);
}
if(NF == 5 && $3 == "A") {
   split($4,hostip,".");
   if(hostip[3] == "1")
   printf("%s\tIN\tPTR\t%s.domain.com.\n",hostip[4],$1);
}
if(NF == 5 && $4 == "A") {
   split($5,hostip,".");
   if(hostip[3] == "1")
   printf("%s\tIN\tPTR\t%s.domain.com.\n",hostip[4],$1);
}
}

