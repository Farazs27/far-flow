#!/usr/bin/env python3
"""Generate reproducible on-device synthetic smoke fixtures; not a personal-voice accuracy test."""
import json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
EXAMPLES=[('EN01', 'en', 'Can we move the design review to three tomorrow?'), ('EN02', 'en', "Let's meet at two, actually three."), ('EN03', 'en', 'Please send the updated proposal this afternoon.'), ('EN04', 'en', 'I do not want to cancel the appointment.'), ('EN05', 'en', 'The total is twenty euros and fifty cents.'), ('EN06', 'en', 'First review the draft. Second check the links. Third send feedback.'), ('EN07', 'en', 'Please add Far Flow to the agenda.'), ('EN08', 'en', 'We should not ship this today, but we can test it.'), ('NL01', 'nl', 'Kunnen we de afspraak naar morgen verplaatsen?'), ('NL02', 'nl', 'Laten we om twee uur afspreken, nee, om drie uur.'), ('NL03', 'nl', 'Kun je het voorstel vanmiddag versturen?'), ('NL04', 'nl', 'Ik wil de afspraak niet annuleren.'), ('NL05', 'nl', 'Het bedrag is twintig euro en vijftig cent.'), ('NL06', 'nl', 'Controleer de tekst, bekijk de links en stuur feedback.'), ('NL07', 'nl', 'Voeg Far Flow toe aan de agenda.'), ('NL08', 'nl', 'We kunnen dit vandaag testen, maar nog niet publiceren.'), ('MX01', 'auto', 'Kun je de pull request reviewen voor de meeting?'), ('MX02', 'auto', 'Please check de laatste versie before we send it.')]
clips=[]
for ident,language,text in EXAMPLES:
 path=ROOT/'Benchmarks/Fixtures'/(ident+'.aiff');path.parent.mkdir(parents=True,exist_ok=True)
 if not path.exists():subprocess.run(['say','-v','Daniel' if language=='en' or ident=='MX02' else 'Xander','-r','155','-o',str(path),text],check=True)
 clips.append({'id':ident,'language':language,'reference':text,'path':path.relative_to(ROOT).as_posix()})
(ROOT/'Benchmarks/corpus.json').write_text(json.dumps(clips,indent=2,ensure_ascii=False))
print('Prepared',len(clips),'synthetic fixtures.')
