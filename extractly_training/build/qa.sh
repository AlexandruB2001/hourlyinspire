set -e
cd /home/user/hourlyinspire/extractly_training/build
python3 build_deck.py
SK=/root/.claude/skills/synced/d39375e1-936f-4251-94d6-49502fcdc5c4_b825d5c7-3e7f-4d02-9d72-3f88ab898cf2/pptx
python3 $SK/scripts/office/validate.py ../Extractly_Training_Melo_LLP_2026.pptx | tail -2
cd qa; rm -f *.pdf s-*.jpg
python3 $SK/scripts/office/soffice.py --headless --convert-to pdf ../../Extractly_Training_Melo_LLP_2026.pptx >/dev/null 2>&1
pdftoppm -jpeg -r 100 Extractly_Training_Melo_LLP_2026.pdf s 2>/dev/null
ls s-*.jpg | wc -l
