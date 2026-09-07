"""Organize images already downloaded with the CUA browser; no network access."""
from pathlib import Path
import json, shutil, hashlib, re
from PIL import Image, ImageDraw
DEST=Path('/home/impulse/Downloads/The Sims 4 References')
TEMP=Path('/tmp/browser-use/assets')
ROWS='''build_rooms_walls_foundations|https://www.carls-sims-4-guide.com/tutorials/building/houses.php|49d23e5c-792d-43d1-9f77-17c10d021479
relationships|https://www.carls-sims-4-guide.com/relationships/|3af095d1-da29-480a-9bbb-50195ef1577f
romance|https://www.carls-sims-4-guide.com/relationships/romance.php|2631c2d6-7a8a-4aa2-8fb1-546fc6cbdf5b
career_progression|https://www.carls-sims-4-guide.com/careers/tips.php|c705d8d5-af49-4be2-954e-86dbbe1220de
needs_identity_aging|https://www.carls-sims-4-guide.com/tutorials/sims.php|67a15edf-aa41-450b-be13-8ea72891a33c
aspiration_icons|https://www.carls-sims-4-guide.com/aspirations/|ba33cf93-4927-48c3-884c-71803842ed86
traits|https://www.carls-sims-4-guide.com/traits/|630944b5-7169-45de-a937-b71fb139fc55
newborns_pregnancy|https://www.carls-sims-4-guide.com/parenting/babies.php|491b9247-7711-40e0-82a5-0ad863e3bbfa
children|https://www.carls-sims-4-guide.com/parenting/children.php|86f4e8f3-004c-4796-81e6-015607eeafb5
toddlers|https://www.carls-sims-4-guide.com/parenting/toddlers.php|9fea8cf5-0984-4d57-a97a-4978cb20cb0d
death|https://www.carls-sims-4-guide.com/death/index.php|d3a3a0cb-0921-4c0e-a1f7-8d786b629c2d
interior_decoration|https://www.carls-sims-4-guide.com/tutorials/building/decorating-inside.php|f1bdbeaa-7978-403e-bcca-2b6ea2df0999
roofs|https://www.carls-sims-4-guide.com/tutorials/building/roofs.php|749708aa-ac2c-45a8-a80d-04299baa98ea
stairs_basements|https://www.carls-sims-4-guide.com/tutorials/building/stairs-basements.php|de75753b-bcae-488b-a733-028e019f03bd
landscaping_pools|https://www.carls-sims-4-guide.com/tutorials/building/decorating-landscaping.php|162c7f2f-54ed-4ea4-9006-f9acb960ebea
emotions|https://www.carls-sims-4-guide.com/emotions/|e4b72118-d4df-4007-87ef-ee113166d0d0
gardening|https://www.carls-sims-4-guide.com/skills/gardening/|b0754123-c303-4f57-ae70-72c657303f08
cooking|https://www.carls-sims-4-guide.com/skills/gourmetcooking/|f16abc03-fa82-49ef-93b4-6e1db4ec95cc
handiness|https://www.carls-sims-4-guide.com/skills/handiness/|36c9e1da-9705-46b9-b600-914fa9489030
painting|https://www.carls-sims-4-guide.com/skills/painting/|bc36b84d-89d7-400a-bbeb-611f962d87de
programming|https://www.carls-sims-4-guide.com/skills/programming/|6ae333d0-fc6b-441f-b17a-fc1d13b71c25
moving_households|https://www.carls-sims-4-guide.com/tutorials/moving-sims.php|9a99e632-cdbf-4e98-8e84-9ddb8545e313
household_rotation|https://www.carls-sims-4-guide.com/tutorials/rotational-play.php|8cc2fbaa-0bce-4b00-89c9-2b44f6ba3925
gallery|https://www.carls-sims-4-guide.com/gallery/|2a3a82f3-7dc5-4862-bacd-0e48c58db3a4
career_selection|https://www.carls-sims-4-guide.com/careers/|235177a6-9f70-4413-a9c2-6aa2fdd59652
skills_overview|https://www.carls-sims-4-guide.com/skills/|02cb9624-2cf9-4f5c-97c9-58869413a4ef
current_identity_romance|https://help.ea.com/en/articles/the-sims/the-sims-4/gender-romance-attraction-guide/|60756e5e-ed02-433e-9dd6-f9ed250febbe
infant_care|https://simscommunity.info/2023/03/15/sims-4-infant-care-guide/|fa41b579-f638-4008-90bc-da56e1fecf16
wants_fears|https://simscommunity.info/2022/07/27/guide-to-wants-and-fears-in-the-sims-4/|fde99e48-59ce-49a9-9c9d-a38365aac5f1
bills_inventory|https://www.carls-sims-4-guide.com/june-2020-patch.php|5ea88c3e-f908-4c2d-8f12-348a2114b056
neighborhood_stories|https://www.ggrecon.com/guides/sims4-neighbourhood-stories/|ccec2328-8f65-47d6-b05c-150d487333a1
phone_services|https://simscommunity.info/2022/11/07/the-sims-4-beginners-guide-to-your-sims-phone/|160e35ef-1fd0-4e02-9ede-087ce551a661
calendar_seasons|https://forums.ea.com/discussions/the-sims-4-general-discussion-en/calendar-comparison-seasons-vs-base-game/1210826|cec198cd-5877-4888-9767-476a6e0b37df'''
def main():
    original=json.loads((DEST/'archive_manifest.json').read_text())
    entries={a['url']:a for a in original['assets']}
    pages=[]
    for row in ROWS.splitlines():
        topic,page,mid=row.split('|'); folder=DEST/'topics'/topic;folder.mkdir(parents=True,exist_ok=True)
        manifest=TEMP/mid/'manifest.json'; shutil.copy2(manifest,DEST/'manifests'/f'{mid}.json')
        assets=[]
        for asset in json.loads(manifest.read_text())['assets']:
            if 'patron2' in asset['url']: continue
            source=Path(asset['path']); output=folder/(asset['id'][:8]+'_'+asset['name']);shutil.copy2(source,output)
            im=Image.open(output)
            a=dict(asset,archive_path=str(output.relative_to(DEST)),width=im.width,height=im.height,format=im.format,topic=topic,source_page=page,sha256=hashlib.sha256(output.read_bytes()).hexdigest())
            entries[a['url']]=a;assets.append(a)
        pages.append(dict(topic=topic,source_page=page,manifest=f'manifests/{mid}.json',asset_paths=[a['archive_path'] for a in assets]))
        screenshots=[a for a in assets if a['width']>=250 and a['height']>=140]
        for page_idx,start in enumerate(range(0,len(screenshots),12)):
            batch=screenshots[start:start+12];sheet=Image.new('RGB',(1440,1200),(22,28,37));d=ImageDraw.Draw(sheet)
            for i,a in enumerate(batch):
                im=Image.open(DEST/a['archive_path']).convert('RGB');im.thumbnail((468,264));x=(i%3)*480+6;y=(i//3)*300+4
                sheet.paste(im,(x,y));d.text((x,y+267),a['name'][:68],fill='white')
            (DEST/'contact_sheets').mkdir(exist_ok=True);sheet.save(DEST/'contact_sheets'/f'{topic}_{page_idx+1}.jpg',quality=90)
    assets=list(entries.values())
    for a in assets:
        if 'sha256' not in a: a['sha256']=hashlib.sha256((DEST/a['archive_path']).read_bytes()).hexdigest()
    content_hashes={a['sha256'] for a in assets}
    large_hashes={a['sha256'] for a in assets if a['width']>=250 and a['height']>=140}
    data=dict(download_method='CUA browser pageAssets.list and pageAssets.bundle from rendered source pages; no network downloader used',date='2026-09-07',reference_only=True,unique_urls=len(assets),unique_image_contents=len(content_hashes),screenshot_sized_unique_contents=len(large_hashes),note='Screenshot-sized counts include article/title composites, tutorial crops, and career preview images, not only full-screen screenshots. Icons remain separately archived.',assets=assets)
    (DEST/'archive_manifest.json').write_text(json.dumps(data,indent=2));(DEST/'source_pages.json').write_text(json.dumps(pages,indent=2))
    print({k:v for k,v in data.items() if k!='assets'})
if __name__=='__main__':main()
